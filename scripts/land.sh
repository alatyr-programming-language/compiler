#!/usr/bin/env bash
# scripts/land.sh — the only path to `main`.
#
# ## Why a script and not a paragraph
#
# There is no CI. Nothing on GitHub runs the gate, so the merge button computes a NEW merge commit at
# the instant of the click, against whatever `main` is then — a tree no gate has ever seen. That is
# worse here than in an ordinary repository for one specific reason: `scripts/corpus.manifest` is a
# whole-tree behaviour oracle, and so are the fixpoint and `idiom_gate.sh`. Two independently green
# pull requests can merge textually clean into a tree whose manifest matches NEITHER of them, and
# nothing would notice until someone ran the gate by hand, days and several merges later, bisecting to
# a merge commit rather than to a change.
#
# So: the object that is gated is the object that is published, by identity. Nothing is re-derived
# between the gate and the push.
#
# ## Why the phases are not chained
#
# A destructive action must never share an `&&` chain with its own verification. A failed fast-forward
# followed by a successful `git branch -D` once lost a lane's work, recovered only from dangling
# commits. `gh pr merge --delete-branch` is that same shape wearing a nicer name: a state change plus
# a deletion in one action, whose precondition is textual mergeability rather than a green gate. This
# script therefore prints a verdict between phases and stops; the push is a separate invocation and
# the branch deletion is a third, with `git merge-base --is-ancestor` as its own precondition.
#
# ## Usage
#
#   scripts/land.sh <pr-number> [--push] [--no-rewalk]
#       prepare + gate the merge, print the push command, stop; with --push, publish it if green.
#       --no-rewalk skips the ~160 s corpus re-walk that spot-checks a predicted oracle commit (below).
#   scripts/land.sh --self-test          exercise the PR-shape, provenance and oracle-commit deciders
#                                        without GitHub or a merge
#
#   ALATYR_LAND_ACCEPT_BASE=<sha>  acknowledge, for this one run, that origin/main's tip <sha> did NOT
#                                  come through a pull request (see "PHASE 1 — provenance" below)
#
# An intentional behaviour change that moves `scripts/corpus.manifest` is gated ONCE. The feature PR
# stays oracle-free and DECLARES the shift in `scripts/corpus.expected-delta` (written by
# `scripts/corpus_manifest.sh --emit-expected`, reviewed in the PR's diff, part of the gated object).
# When the gate on the merge is green and its corpus stage reports `match by the declared delta`,
# PHASE 6a commits the fresh manifest that run generated as a one-file oracle commit on top of the merge,
# proves it is that file byte for byte and touches nothing else, runs the `xbackend_diff.sh` ratchet on
# it, and publishes THAT object. The ratchet runs on the FRESH manifest, never on the committed one:
# while the oracle commit is still pending, the committed manifest still contains the rows that have
# demonstrably moved, so a ratchet run before it cannot see the improvement — it reports the old count
# unchanged through the whole gate and drops only after the oracle commit. Ordering is the assertion.
#
# The second full gate it replaces could only ever have differed from
# the first in those two manifest-reading checks; everything else the gate runs is a function of the
# source tree, and an oracle commit changes no source byte.
#
# Without a delta file nothing changed: an oracle mismatch is a red gate, the merged tree is left
# detached for inspection, and the maintainer's separate oracle commit plus a complete second gate is
# the path (alatyr-integrate §4). `idiom.baseline` and `needle.baseline` always take that path.
#
# Run it from the integration checkout, inside `nix develop` (or it re-enters via `nix develop -c`).
# This helper fetches one selected PR snapshot and deliberately leaves it for alatyr-integrate §5;
# that procedure deletes the exact snapshot only after successful acceptance.
set -u

SELF="$0"
ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
cd "$ROOT" || exit 2
REPO="${ALATYR_REPO:-alatyr-programming-language/compiler}"

say()  { printf '\n=== %s\n' "$*"; }
die()  { printf 'land: %s\n' "$*" >&2; exit 2; }
verdict() { printf '\n*** %s ***\n' "$*"; }

# A JSON or shell layer that escapes a newline one time too many leaves the two literal characters
# backslash+n in a one-line message. Existing main history contains this debt and is deliberately not
# rescanned here: landing checks the selected PR body and only the commits it introduces, so the check
# prevents new malformed records without rewriting or blocking on old ones. A real newline makes a
# literal \n in prose or a fenced example harmless; trailing transport newlines are not separators.
message_shape_check() {
  local object="$1"
  local message="$2"
  local normalized="$message"
  local literal_backslash_n='\n'
  local real_newline=$'\n'

  while [[ "$normalized" == *"$real_newline" ]]; do
    normalized="${normalized%"$real_newline"}"
  done
  if [[ "$normalized" == *"$literal_backslash_n"* &&
        "$normalized" != *"$real_newline"* ]]; then
    printf '  REFUSE: %s contains literal backslash-n as its only line separator\n' "$object"
    return 1
  fi
  return 0
}

land_message_shape_self_test() {
  local malformed prose fenced output rc

  malformed=$'Summary\\n\\nVerification\n'
  output="$(message_shape_check 'commit deadbeef' "$malformed" 2>&1)"
  rc=$?
  if [ "$rc" = 0 ]; then
    echo 'land self-test: malformed one-line message was accepted' >&2
    return 1
  fi
  case "$output" in
    *'commit deadbeef'*) ;;
    *)
      echo 'land self-test: malformed message did not name the offending object' >&2
      return 1
      ;;
  esac

  prose=$'Summary\n\nThe prose mentions literal \\n as data.\n\nVerification.\n'
  message_shape_check 'PR #prose' "$prose" || {
    echo 'land self-test: a formatted prose example was rejected' >&2
    return 1
  }
  fenced=$'Summary\n\n```text\nliteral \\n\n```\n\nVerification.\n'
  message_shape_check 'PR #fenced' "$fenced" || {
    echo 'land self-test: a formatted fenced example was rejected' >&2
    return 1
  }
  echo 'ok   land message-shape self-test: malformed body rejected; formatted literal examples accepted'
}

# ------------------------------------------------------------------------------------------------
# THE PR-SHAPE REFUSAL DECIDERS (issue #600).
#
# Each of these four is the ONLY thing standing between a malformed PR and a merge, and until this
# issue not one of them was exercised by anything: `--self-test` drove `message_shape_check` alone,
# so `land.sh --self-test` and `full.sh --self-test` both reported green with the oracle-mixing and
# seed-binary refusals turned into notes — measured on the parent. They are factored out here, out
# of PHASE 2's inline `if`s, for the same reason `fmt_classify` was in #599: a decision a self-test
# cannot call is a decision nothing can plant against.
#
# Each returns 0 to allow and 1 to refuse, prints its own REFUSE line, and reads only its
# arguments — no repository state — so the self-test drives the REAL decision without a merge, a
# network call, or a git object.
ORACLE_PATH_RE='^(scripts/corpus\.manifest|scripts/idiom\.baseline|scripts/needle\.baseline)$'

## A feature PR and an oracle regeneration are separate review objects.
pr_oracle_mix_check() { # changed-paths
  local oracle non_oracle
  oracle="$(printf '%s\n' "$1" | grep -E "$ORACLE_PATH_RE" || true)"
  non_oracle="$(printf '%s\n' "$1" | grep -Ev "$ORACLE_PATH_RE" | grep -v '^$' || true)"
  [ -n "$oracle" ] && [ -n "$non_oracle" ] || return 0
  echo "  REFUSE: this PR mixes an oracle path with non-oracle paths. The feature PR must be oracle-free;"
  echo "          the maintainer regenerates each affected oracle after the local merge in its own commit."
  return 1
}

## A reseed is the maintainer's act and its three-stage evidence is not a property of a diff.
pr_seed_binary_check() { # changed-paths
  printf '%s\n' "$1" | grep -qx 'seed/alatyr' || return 0
  echo "  REFUSE: the PR contains seed/alatyr. A reseed is the maintainer's act and its three-stage"
  echo "          evidence is not a property of a diff — GitHub renders it as 'Binary file not shown'."
  return 1
}

## `seed/VERSION` is append-only: never rewrite entries to make old hashes resolve.
pr_seed_version_append_only_check() { # changed-paths deleted-line-count
  printf '%s\n' "$1" | grep -qx 'seed/VERSION' || return 0
  case "${2:-0}" in ''|0) return 0 ;; esac
  echo "  REFUSE: seed/VERSION is append-only and this PR deletes ${2} line(s) from it."
  return 1
}

## A regenerated oracle owns a commit that touches nothing else.
pr_oracle_commit_isolation_check() { # oracle-path commit other-file-count
  case "${3:-0}" in ''|0) return 0 ;; esac
  echo "  REFUSE: commit $2 changes $1 AND $3 other file(s)."
  echo "          A regenerated oracle owns a commit that touches nothing else, or the review is"
  echo "          reading a diff \`.gitattributes\` has told GitHub not to render."
  return 1
}

## The predicted delta must have been predicted against the oracle this merge starts from. Refused
## here, before a 55-minute gate, because the gate would only reach the same verdict at its end: a
## delta whose base is not the committed manifest is INERT, so the walk then needs a byte-for-byte
## match it cannot have. The cure is a rebase and a fresh `--emit-expected`, never a hand edit.
DELTA_REL=scripts/corpus.expected-delta
pr_delta_base_check() { # changed-paths declared-base-sha|absent base-manifest-sha
  printf '%s\n' "$1" | grep -qx "$DELTA_REL" || return 0
  [ "$2" = absent ] && return 0          # the PR deletes a spent delta: nothing is declared
  [ -n "$2" ] && [ "$2" = "$3" ] && return 0
  echo "  REFUSE: $DELTA_REL was predicted against manifest ${2:-<no base_sha256>},"
  echo "          but this merge starts from ${3:-<unknown>}. Rebase onto main and re-emit it with"
  echo "          scripts/corpus_manifest.sh --emit-expected from a walk of the rebased branch."
  return 1
}

## The oracle commit PHASE 6a makes changes the corpus manifest and NOTHING else — the whole argument
## that its source tree was already gated rests on that set being exactly one path.
oracle_commit_paths_check() { # changed-paths-of-the-oracle-commit
  [ "$1" = scripts/corpus.manifest ] && return 0
  echo "  REFUSE: the oracle commit changes {$(printf '%s' "$1" | tr '\n' ' ')} — it must change exactly"
  echo "          {scripts/corpus.manifest}, or the gate on its parent is not a verdict on it."
  return 1
}

## PROVENANCE. `main` is advanced only over commits that came through a pull request: the merge this
## script (or a batch) makes, plus the integrator's own TAIL on top of such a merge — a one-oracle
## commit (the manifest, optionally with the xbackend ratchet line it moves) or a reseed. A direct push
## of anything else was never gated as a landing, and building the next merge on it would quietly make
## the next gate its first one. One step of the first-parent walk from origin/main's tip:
##   0  a merge whose second parent is the head of a PR merged into main — provenance established
##   3  an integrator tail commit — keep walking to its first parent
##   1  anything else — refuse
LAND_TAIL_ORACLE_RE='^(scripts/corpus\.manifest|scripts/idiom\.baseline|scripts/needle\.baseline|scripts/xbackend_diff\.baseline)$'
LAND_TAIL_RESEED_RE='^(package\.al|seed/alatyr|seed/VERSION|scripts/package_cli_test\.sh|CHANGELOG\.md)$'
main_provenance_step() { # parent-count pr-merged(yes|no|-) changed-paths commit
  if [ "$1" -ge 2 ]; then
    [ "$2" = yes ] && return 0
    echo "  REFUSE: main's merge $4 merges a head that is not the head of any PR merged into main."
    return 1
  fi
  if [ "$1" = 1 ] && [ -n "$3" ]; then
    printf '%s\n' "$3" | grep -Evq "$LAND_TAIL_ORACLE_RE" || return 3
    printf '%s\n' "$3" | grep -Evq "$LAND_TAIL_RESEED_RE" || {
      printf '%s\n' "$3" | grep -qx seed/alatyr && return 3; }
  fi
  echo "  REFUSE: main's $4 did not come through a pull request — it is neither a PR merge nor an"
  echo "          oracle or reseed commit on top of one (it changes: $(printf '%s' "$3" | tr '\n' ' '))."
  echo "          Land it through a PR, or, if the owner accepts it as it is, re-run with"
  echo "          ALATYR_LAND_ACCEPT_BASE=<origin/main's full sha> to acknowledge it for this one landing."
  return 1
}

# ------------------------------------------------------------------------------------------------
# THE GATE OF THE GATE. Counted, recorded in files, and run in a SUBSHELL: an unbound variable or
# an arithmetic error inside a driven function unwinds to top level and ENDS THE SCRIPT, so the
# diagnostic written for that case can never print. The marker check below is what notices.
LAND_SELFTEST_EXPECTED=43
land_shape_self_test() { # work-dir
  local st="$1" bad="" k=0 out
  rm -rf "$st"; mkdir -p "$st" || return 1
  _ck() { k=$((k+1)); [ "$1" = 0 ] || bad="$bad $2"; }

  # The pre-existing message-shape self-test, kept exactly as it was and counted as the one
  # verdict it reports. It is deliberately NOT inflated to the three directions it asserts
  # internally: the printed count is proof of work, and a count that credits checks this
  # function did not itself make is the sort of decoration this issue exists to remove.
  land_message_shape_self_test; _ck $? message-shape-self-test

  # ---- 1 · the oracle-mixing refusal, both directions and every oracle. --------------------
  local oracle
  for oracle in scripts/corpus.manifest scripts/idiom.baseline scripts/needle.baseline; do
    out="$(pr_oracle_mix_check "$(printf '%s\n%s' "$oracle" src/lower.al)" 2>&1)"
    [ $? = 1 ]; _ck $? "oracle-mix-allowed-$oracle-beside-a-source-file"
    case "$out" in *'mixes an oracle path with non-oracle paths'*) _ck 0 x ;;
                   *) _ck 1 "oracle-mix-did-not-say-why($oracle)" ;; esac
    pr_oracle_mix_check "$oracle" >/dev/null 2>&1
    _ck $? "oracle-mix-refused-an-oracle-ONLY-PR($oracle)"
  done
  # …and the eraser control: a PR touching no oracle at all must pass. A predicate that refused
  # everything would satisfy every check above and block every landing.
  pr_oracle_mix_check "$(printf '%s\n%s' src/lower.al test/x.al)" >/dev/null 2>&1
  _ck $? oracle-mix-refused-an-ordinary-PR
  # A path that merely LOOKS like an oracle is not one; the anchors in the pattern are load-bearing.
  pr_oracle_mix_check "$(printf '%s\n%s' scripts/corpus.manifest.bak src/lower.al)" >/dev/null 2>&1
  _ck $? oracle-mix-treated-a-lookalike-path-as-an-oracle

  # ---- 2 · the seed binary. ----------------------------------------------------------------
  out="$(pr_seed_binary_check "$(printf '%s\n%s' src/lower.al seed/alatyr)" 2>&1)"
  [ $? = 1 ]; _ck $? seed-binary-allowed-a-PR-carrying-seed/alatyr
  case "$out" in *'A reseed is the maintainer'*) _ck 0 x ;; *) _ck 1 seed-binary-did-not-say-why ;; esac
  pr_seed_binary_check "$(printf '%s\n%s' seed/VERSION src/lower.al)" >/dev/null 2>&1
  _ck $? seed-binary-refused-a-PR-that-does-not-carry-the-binary

  # ---- 3 · seed/VERSION is append-only, and only when it is in the PR at all. --------------
  out="$(pr_seed_version_append_only_check seed/VERSION 4 2>&1)"
  [ $? = 1 ]; _ck $? append-only-allowed-a-deletion-from-seed/VERSION
  case "$out" in *'deletes 4 line(s)'*) _ck 0 x ;; *) _ck 1 append-only-did-not-name-the-deletion-count ;; esac
  pr_seed_version_append_only_check seed/VERSION 0 >/dev/null 2>&1
  _ck $? append-only-refused-a-pure-append
  pr_seed_version_append_only_check src/lower.al 4 >/dev/null 2>&1
  _ck $? append-only-fired-on-a-PR-that-does-not-touch-seed/VERSION

  # ---- 4 · an oracle commit touches that oracle alone. -------------------------------------
  out="$(pr_oracle_commit_isolation_check scripts/corpus.manifest deadbeef 2 2>&1)"
  [ $? = 1 ]; _ck $? oracle-commit-allowed-a-commit-carrying-two-other-files
  case "$out" in *deadbeef*'AND 2 other file(s)'*) _ck 0 x ;;
                 *) _ck 1 oracle-commit-did-not-name-the-commit-and-the-count ;; esac
  pr_oracle_commit_isolation_check scripts/corpus.manifest deadbeef 0 >/dev/null 2>&1
  _ck $? oracle-commit-refused-a-one-file-oracle-commit

  # ---- 5 · the predicted delta's base, checked before the gate. ----------------------------
  out="$(pr_delta_base_check "$(printf '%s\n%s' src/lower.al "$DELTA_REL")" aaaa bbbb 2>&1)"
  [ $? = 1 ]; _ck $? delta-base-allowed-a-delta-predicted-against-another-manifest
  case "$out" in *'predicted against manifest aaaa'*'starts from bbbb'*) _ck 0 x ;;
                 *) _ck 1 delta-base-did-not-name-both-manifests ;; esac
  pr_delta_base_check "$(printf '%s\n%s' src/lower.al "$DELTA_REL")" bbbb bbbb >/dev/null 2>&1
  _ck $? delta-base-refused-a-delta-predicted-against-this-merge-base
  pr_delta_base_check "$(printf '%s\n%s' src/lower.al "$DELTA_REL")" '' bbbb >/dev/null 2>&1
  [ $? = 1 ]; _ck $? delta-base-allowed-a-delta-with-no-base
  pr_delta_base_check src/lower.al aaaa bbbb >/dev/null 2>&1
  _ck $? delta-base-fired-on-a-PR-that-does-not-carry-a-delta
  pr_delta_base_check "$DELTA_REL" absent bbbb >/dev/null 2>&1
  _ck $? delta-base-refused-the-deletion-of-a-spent-delta

  # ---- 6 · the oracle commit PHASE 6a makes is exactly one path. ----------------------------
  oracle_commit_paths_check scripts/corpus.manifest >/dev/null 2>&1
  _ck $? oracle-paths-refused-a-manifest-only-commit
  oracle_commit_paths_check "$(printf '%s\n%s' scripts/corpus.manifest src/lower.al)" >/dev/null 2>&1
  [ $? = 1 ]; _ck $? oracle-paths-allowed-a-source-file-beside-the-manifest
  oracle_commit_paths_check "$(printf '%s\n%s' scripts/corpus.manifest scripts/xbackend_diff.baseline)" >/dev/null 2>&1
  [ $? = 1 ]; _ck $? oracle-paths-allowed-the-ratchet-line-beside-the-manifest
  oracle_commit_paths_check '' >/dev/null 2>&1
  [ $? = 1 ]; _ck $? oracle-paths-allowed-an-empty-commit

  # ---- 7 · provenance of origin/main's tip. ------------------------------------------------
  main_provenance_step 2 yes '' m1 >/dev/null 2>&1; _ck $? provenance-refused-a-PR-merge
  main_provenance_step 2 no '' m2 >/dev/null 2>&1; [ $? = 1 ]; _ck $? provenance-allowed-a-merge-of-no-PR
  out="$(main_provenance_step 1 - docs/ir-slice-3.md 3381d25 2>&1)"
  [ $? = 1 ]; _ck $? provenance-allowed-a-direct-push
  case "$out" in *3381d25*'docs/ir-slice-3.md'*ALATYR_LAND_ACCEPT_BASE*) _ck 0 x ;;
                 *) _ck 1 provenance-did-not-name-the-commit-its-paths-and-the-acknowledgement ;; esac
  main_provenance_step 1 - scripts/corpus.manifest o1 >/dev/null 2>&1
  [ $? = 3 ]; _ck $? provenance-stopped-at-an-oracle-commit
  main_provenance_step 1 - "$(printf '%s\n%s' scripts/corpus.manifest scripts/xbackend_diff.baseline)" o2 >/dev/null 2>&1
  [ $? = 3 ]; _ck $? provenance-stopped-at-a-manifest-plus-ratchet-commit
  main_provenance_step 1 - "$(printf '%s\n' package.al seed/alatyr seed/VERSION scripts/package_cli_test.sh CHANGELOG.md)" r1 >/dev/null 2>&1
  [ $? = 3 ]; _ck $? provenance-stopped-at-a-reseed-commit
  main_provenance_step 1 - CHANGELOG.md c1 >/dev/null 2>&1
  [ $? = 1 ]; _ck $? provenance-allowed-a-direct-CHANGELOG-push-as-a-reseed
  main_provenance_step 1 - "$(printf '%s\n%s' scripts/corpus.manifest src/lower.al)" x1 >/dev/null 2>&1
  [ $? = 1 ]; _ck $? provenance-allowed-a-source-change-riding-an-oracle-commit
  main_provenance_step 0 - '' root >/dev/null 2>&1
  [ $? = 1 ]; _ck $? provenance-allowed-a-root-commit

  # ---- 8 · the predicted-delta decider in corpus_manifest.sh, which PHASE 6a relies on. ------
  bash "$ROOT/scripts/corpus_manifest.sh" --delta-self-test >"$st/delta.out" 2>&1
  _ck $? "corpus-manifest-predicted-delta-self-test($(tail -3 "$st/delta.out" | tr '\n' ' '))"

  printf '%s' "$bad" > "$st/bad"; printf '%s' "$k" > "$st/checks"; : > "$st/complete"
  if [ -n "$bad" ]; then echo "*** land self-test: FAILED —$bad ***" >&2; return 1; fi
  if [ "$k" -lt "$LAND_SELFTEST_EXPECTED" ]; then
    echo "*** land self-test: ran $k checks, expected at least $LAND_SELFTEST_EXPECTED — a self-test" >&2
    echo "    that reports fewer checks than it owes is a failure, not a shortcut to green ***" >&2
    return 1
  fi
  echo "ok   land PR-shape self-test: $k checks — the oracle-mixing, seed-binary, seed/VERSION"
  echo "     append-only, one-file-oracle-commit, predicted-delta base, oracle-commit path-set and"
  echo "     main-provenance refusals, each in both directions, and the predicted-delta decider"
  return 0
}

if [ "${1:-}" = '--self-test' ]; then
  LAND_ST="$(mktemp -d)"
  ( land_shape_self_test "$LAND_ST" ); LAND_ST_RC=$?
  if [ ! -f "$LAND_ST/complete" ]; then
    echo "land self-test: did NOT run to completion (rc=$LAND_ST_RC) — it recorded no verdict, so" >&2
    echo "     this run proves nothing about the PR-shape refusals" >&2
    rm -rf "$LAND_ST"; exit 1
  fi
  if [ -s "$LAND_ST/bad" ]; then
    echo "land self-test: recorded failures — $(cat "$LAND_ST/bad")" >&2; rm -rf "$LAND_ST"; exit 1
  fi
  if [ "$(cat "$LAND_ST/checks")" -lt "$LAND_SELFTEST_EXPECTED" ]; then
    echo "land self-test: recorded $(cat "$LAND_ST/checks") checks, expected at least $LAND_SELFTEST_EXPECTED" >&2
    rm -rf "$LAND_ST"; exit 1
  fi
  rm -rf "$LAND_ST"
  exit "$LAND_ST_RC"
fi

PR="${1:-}"
case "$PR" in
  ''|*[!0-9]*) sed -n '/^# ## Usage/,/^set -u/p' "$SELF" | sed -e 's/^# \{0,1\}//' -e '$d'; exit 2 ;;
esac
DO_PUSH=0
DO_REWALK=1
for a in "${@:2}"; do
  case "$a" in
    --push) DO_PUSH=1 ;;
    --no-rewalk) DO_REWALK=0 ;;
    *) die "unknown option: $a" ;;
  esac
done
sha256_of() { if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi; }

# --- PHASE 0 — preconditions ----------------------------------------------------------------------
# Each of these has cost somebody a measurement. A dirty tree makes "the gate ran on the merge" false;
# a stash means uncommitted work exists that the gate cannot see; a missing `gh` means the PR head
# cannot be fetched at all.
say "PHASE 0 — preconditions"
command -v gh  >/dev/null 2>&1 || die "gh is required to resolve PR #$PR"
command -v git >/dev/null 2>&1 || die "git is required"
[ -z "$(git status --porcelain)" ] || die "the integration checkout is dirty; commit or clean it first"
[ -z "$(git stash list)" ] || die "a stash exists. \`git stash\` is forbidden here (one ref per repository,
     and two trees stashing at once swap each other's work). Resolve it before landing."
git rev-parse --verify -q refs/heads/main >/dev/null || die "no local main"
echo "  clean tree, no stash, gh present"

ISSUE_META="$(gh pr view "$PR" -R "$REPO" --json body,title \
          --jq '[.body, .title] | join(" ")
                | capture("(?i)(?<relation>closes|fixes|resolves|refs) #[[:space:]]*(?<number>[0-9]+)")
                | "\(.relation | ascii_downcase)|\(.number)"' 2>/dev/null || true)"
RELATION="${ISSUE_META%%|*}"
ISSUE="${ISSUE_META#*|}"
case "$RELATION" in
  closes)   ISSUE_LINK="Closes #$ISSUE" ;;
  fixes)    ISSUE_LINK="Fixes #$ISSUE" ;;
  resolves) ISSUE_LINK="Resolves #$ISSUE" ;;
  refs)     ISSUE_LINK="Refs #$ISSUE" ;;
  *)        RELATION=; ISSUE=; ISSUE_LINK= ;;
esac
HEAD_LABEL="$(gh pr view "$PR" -R "$REPO" --json headRefName --jq .headRefName 2>/dev/null || true)"
HEAD_OID="$(gh pr view "$PR" -R "$REPO" --json headRefOid --jq .headRefOid 2>/dev/null || true)"
IS_FORK="$(gh pr view "$PR" -R "$REPO" --json headRepositoryOwner \
            --jq 'if .headRepositoryOwner.login == "alatyr-programming-language" then "no" else "yes" end' 2>/dev/null || echo unknown)"
echo "  PR #$PR  head=${HEAD_LABEL:-?}  issue=${ISSUE_LINK:-<none declared>}  fork=$IS_FORK"
[ -n "$ISSUE_LINK" ] || echo "  NOTE: no valid issue relation in the PR — verify the issue linkage before landing."
[ "$RELATION" = refs ] && echo "  NOTE: bounded slice — the referenced issue remains open; record landed and residual scope in acceptance."
[ -n "$HEAD_OID" ] || die "could not resolve the selected PR head"

say "PHASE 1 — fetch the PR head"
PR_REF="refs/remotes/pr/$PR"
git fetch --quiet origin main "refs/pull/$PR/head:$PR_REF" || die "fetch failed"
git rev-parse --verify -q "$PR_REF" >/dev/null || die "no selected PR head on origin"
BASE="$(git rev-parse origin/main)"
HEAD_SHA="$(git rev-parse "$PR_REF")"
[ "$HEAD_SHA" = "$HEAD_OID" ] || die "selected PR head changed while fetching"
echo "  base=$BASE"
echo "  head=$HEAD_SHA"

# --- PHASE 1b — provenance of the base -------------------------------------------------------------
# The merge below is built ON origin/main, and the push advances main over it, so whatever sits at
# origin/main's tip is published again under this PR's gate. A commit pushed straight to main never
# went through a landing — no PR, no audit, no gate on that object as a landing — and building on it
# silently makes this PR's gate its first one. Walk the first-parent chain from the tip: the
# integrator's tail commits (an oracle or a reseed) are passed over, and the first other commit must be
# a merge of a PR that GitHub records as merged into main. Earlier history is not rescanned; each
# landing proves its own base, so the chain is proved one link at a time from here on.
say "PHASE 1b — provenance: origin/main's tip came through a pull request"
prov_c="$BASE"; prov_ok=1; prov_n=0
while :; do
  set -- $(git rev-list --parents -n 1 "$prov_c")
  prov_np=$(($# - 1)); prov_v=-; prov_files=
  if [ "$prov_np" -ge 2 ]; then
    prov_p2="$3"
    prov_count="$(gh api "repos/$REPO/commits/$prov_p2/pulls" \
      --jq "[.[] | select(.merged_at != null and .head.sha == \"$prov_p2\" and .base.ref == \"main\")] | length" \
      2>/dev/null)" || die "could not ask GitHub which PR merged $prov_p2; provenance unknown, refusing"
    case "$prov_count" in ''|*[!0-9]*) die "unreadable PR association for $prov_p2; refusing" ;; esac
    [ "$prov_count" -ge 1 ] && prov_v=yes || prov_v=no
  else
    prov_files="$(git diff-tree --no-commit-id --name-only -r "$prov_c")"
  fi
  main_provenance_step "$prov_np" "$prov_v" "$prov_files" "$(git rev-parse --short "$prov_c")"; prov_rc=$?
  case "$prov_rc" in
    0) echo "  $(git rev-parse --short "$prov_c") merges a PR head GitHub records as merged into main"; break ;;
    3) echo "  $(git rev-parse --short "$prov_c") is an integrator tail commit ($(printf '%s' "$prov_files" | tr '\n' ' '))"
       prov_c="$(git rev-parse "$prov_c^")"; prov_n=$((prov_n + 1))
       [ "$prov_n" -le 8 ] || { echo "  REFUSE: more than 8 tail commits above the last PR merge"; prov_ok=0; break; } ;;
    *) prov_ok=0; break ;;
  esac
done
if [ "$prov_ok" = 0 ]; then
  if [ -n "${ALATYR_LAND_ACCEPT_BASE:-}" ] && [ "$ALATYR_LAND_ACCEPT_BASE" = "$BASE" ]; then
    echo "  ACKNOWLEDGED by the operator (ALATYR_LAND_ACCEPT_BASE=$BASE): main's tip is accepted as it is."
    echo "  Record that acknowledgement in this PR's acceptance comment."
  else
    [ -n "${ALATYR_LAND_ACCEPT_BASE:-}" ] && echo "  (ALATYR_LAND_ACCEPT_BASE=$ALATYR_LAND_ACCEPT_BASE is not origin/main's tip $BASE)"
    verdict "LAND REFUSED (provenance of main) — nothing was merged"
    exit 1
  fi
fi

# The shape checks that are cheap, mechanical, and each anchored to an incident.
say "PHASE 2 — PR shape"
shape_fail=0
CHANGED="$(git diff --name-only "$BASE...$HEAD_SHA")"
# The PR body is mutable GitHub metadata, so read it after the immutable head was fetched and checked.
# Commit messages are read from the fetched objects, not executed; only BASE..HEAD is inspected, while
# the 39 historical malformed bodies already reachable from main remain grandfathered.
PR_BODY="$(gh pr view "$PR" -R "$REPO" --json body --jq .body 2>/dev/null)" || die "could not read the selected PR body"
message_shape_check "PR #$PR body" "$PR_BODY" || shape_fail=1
for c in $(git rev-list "$BASE..$HEAD_SHA"); do
  COMMIT_OBJECT="$(git cat-file commit "$c")" || die "could not read commit $c"
  COMMIT_MESSAGE="${COMMIT_OBJECT#*$'\n\n'}"
  COMMIT_BODY="${COMMIT_MESSAGE#*$'\n\n'}"
  message_shape_check "commit $c" "$COMMIT_BODY" || shape_fail=1
done
# A feature PR and an oracle regeneration are separate review objects. Checking each oracle commit in
# isolation is not enough: a PR can otherwise hide a feature change beside an oracle-only commit, and
# the resulting combined review would violate the worker/maintainer boundary even when both commits
# are individually one-file-shaped.
pr_oracle_mix_check "$CHANGED" || shape_fail=1
pr_seed_binary_check "$CHANGED" || shape_fail=1
DELTA_DECLARED_BASE=absent
if git cat-file -e "$HEAD_SHA:$DELTA_REL" 2>/dev/null; then
  DELTA_DECLARED_BASE="$(git show "$HEAD_SHA:$DELTA_REL" | sed -n 's/^base_sha256=//p' | head -n 1)"
fi
BASE_MANIFEST_SHA="$(git show "$BASE:scripts/corpus.manifest" | sha256_of)"
pr_delta_base_check "$CHANGED" "$DELTA_DECLARED_BASE" "$BASE_MANIFEST_SHA" || shape_fail=1
printf '%s\n' "$CHANGED" | grep -qx "$DELTA_REL" && [ "$DELTA_DECLARED_BASE" != absent ] &&
  echo "  predicted delta: $DELTA_REL declares $(git show "$HEAD_SHA:$DELTA_REL" | sed -n 's/^pairs=//p') pair(s) against main's manifest"
dels=0
printf '%s\n' "$CHANGED" | grep -qx 'seed/VERSION' &&
  dels="$(git diff --numstat "$BASE...$HEAD_SHA" -- seed/VERSION | awk '{print $2}')"
pr_seed_version_append_only_check "$CHANGED" "${dels:-0}" || shape_fail=1
for oracle in scripts/corpus.manifest scripts/idiom.baseline scripts/needle.baseline; do
  printf '%s\n' "$CHANGED" | grep -qx "$oracle" || continue
  # An oracle regeneration owns its own commit. Squash/rebase merging is disabled at the repo level
  # for exactly this reason; here we check the commits that actually exist.
  for c in $(git rev-list "$BASE..$HEAD_SHA" -- "$oracle"); do
    others="$(git show --name-only --format= "$c" | grep -v "^$oracle$" | grep -c '' || true)"
    pr_oracle_commit_isolation_check "$oracle" "$(git rev-parse --short "$c")" "$others" || shape_fail=1
  done
done
# A path with history is a resurrection: a lane once overwrote a stronger existing fixture that way.
for f in $(git diff --name-only --diff-filter=A "$BASE...$HEAD_SHA"); do
  [ -n "$(git log --oneline -1 -- "$f" 2>/dev/null)" ] || continue
  echo "  WARN: $f is added by this PR but has history. Read \`git log -- $f\` before landing."
done
[ "$shape_fail" = 0 ] && echo "  shape ok"
[ "$shape_fail" = 0 ] || { verdict "LAND REFUSED (PR shape) — nothing was merged"; exit 1; }
[ "$IS_FORK" = yes ] && {
  echo
  echo "  This PR is from a FORK. The gate below compiles and RUNS its fixtures — freestanding"
  echo "  programs making raw syscalls, under qemu and wasmtime — and invokes whatever scripts/e2e.sh"
  echo "  the checkout contains. Read these diffs line by line before continuing:"
  git diff --name-only "$BASE...$HEAD_SHA" -- scripts/ test/ | sed 's/^/    /'
}

# --- PHASE 3 — build the merge locally ------------------------------------------------------------
say "PHASE 3 — merge locally (--no-ff, so the PR head stays an ancestor and GitHub marks it Merged)"
git switch --quiet --detach "$BASE" || die "could not detach at base"
msg="merge #$PR: ${HEAD_LABEL:-pr-$PR}"
[ -n "$ISSUE_LINK" ] && msg="$msg

$ISSUE_LINK"
git merge --no-ff --no-verify -m "$msg" "$PR_REF" >/dev/null 2>&1 || {
  git merge --abort 2>/dev/null
  git switch --quiet - 2>/dev/null
  verdict "LAND REFUSED (the merge conflicts) — ask for a rebase onto $BASE"
  exit 1
}
M="$(git rev-parse HEAD)"
echo "  merged as $M"
echo "  a reseed, if one is owed, is committed ON TOP OF THIS COMMIT, before the gate runs —"
echo "  so that the fixpoint that is verified is the fixpoint that ships."

# --- PHASE 4 — the authoritative gate, on the merge -----------------------------------------------
say "PHASE 4 — the authoritative gate, on the merged tree"
GATE_STAMP="$ROOT/target/land-gate.stamp"
mkdir -p "$ROOT/target" && : > "$GATE_STAMP"
( ulimit -c 0; nix develop -c bash scripts/full.sh --force-sweeps )
gate_rc=$?
echo "  full.sh exited $gate_rc"

# --- PHASE 5 — assert the tree the gate ran on did not move ---------------------------------------
# This is the REAL version of the "git status is clean" claim. A clean status does not prove the
# manifest ran in --check rather than --write: a committed --write regeneration leaves it clean too.
# What proves it is that the gated tree is unchanged, checked against the index and the worktree
# separately, plus the commit-shape check in PHASE 2.
say "PHASE 5 — post-gate assertions"
post_fail=0
git diff --exit-code --quiet        || { echo "  FAIL: the worktree moved during the gate"; post_fail=1; }
git diff --cached --exit-code --quiet || { echo "  FAIL: the index moved during the gate"; post_fail=1; }
git diff --exit-code --quiet -- scripts/corpus.manifest scripts/idiom.baseline scripts/needle.baseline \
  || { echo "  FAIL: an oracle file was rewritten by the gate (a --write slipped in)"; post_fail=1; }
[ "$M" = "$(git rev-parse HEAD)" ] || { echo "  FAIL: HEAD is no longer the gated commit"; post_fail=1; }
[ "$post_fail" = 0 ] && echo "  the gated tree is exactly $M"

# --- PHASE 6 — the verdict, and then STOP ---------------------------------------------------------
if [ "$gate_rc" != 0 ] || [ "$post_fail" != 0 ]; then
  verdict "NOT LANDABLE — gate rc $gate_rc, post-gate assertions $([ "$post_fail" = 0 ] && echo ok || echo FAILED)"
  echo "The merge commit $M is left in place, detached, for inspection. \`git switch main\` to leave it."
  exit 1
fi

# --- PHASE 6a — the predicted oracle commit, when the gate realised a declared delta ----------------
# The corpus stage passed by `match by the declared delta`: the fresh walk differs from the committed
# manifest by exactly the rows the feature declared, and it left that fresh manifest in target/. That
# file IS the oracle. Commit it byte for byte on top of M, prove the commit is that file and changes
# nothing else, and run the one other gate check that reads the manifest as data — the xbackend
# ratchet, which is arithmetic over the manifest and needs no compiler. Every other stage of a second
# full gate is a function of the source tree, which this commit does not touch. A re-walk of the
# corpus on the new object (~160 s, not ~55 min) is kept as a DETERMINISM spot-check of the walk, not
# as the verdict. M alone is never published from here: its committed oracle would be stale.
CM_LOG="$ROOT/target/full_corpus_manifest.log"
FRESH="$ROOT/target/corpus-manifest/corpus.manifest"
PUBLISH="$M"
if [ -f "$CM_LOG" ] && [ "$CM_LOG" -nt "$GATE_STAMP" ] && grep -q '^corpus manifest: match by the declared delta' "$CM_LOG"; then
  say "PHASE 6a — the predicted oracle commit (the gate realised $DELTA_REL exactly)"
  o_fail=0
  [ -f "$FRESH" ] && [ "$FRESH" -nt "$GATE_STAMP" ] || die "the gate's fresh manifest $FRESH is missing or older than this gate"
  # Re-decide from the files rather than trusting the log line.
  bash scripts/corpus_manifest.sh --check-delta scripts/corpus.manifest "$FRESH" "$DELTA_REL" || {
    verdict "NOT LANDABLE — the fresh manifest does not realise $DELTA_REL when re-checked"; exit 1; }
  O_RESULT="$(sed -n 's/^result_sha256=//p' "$DELTA_REL" | head -n 1)"
  [ "$(sha256_of < "$FRESH")" = "$O_RESULT" ] || { echo "  FAIL: fresh manifest is not result_sha256"; o_fail=1; }
  O_RATCHET="$(bash scripts/xbackend_diff.sh --self-test >/dev/null 2>&1 && bash scripts/xbackend_diff.sh --ratchet "$FRESH" 2>&1)"
  o_ratchet_rc=$?
  printf '%s\n' "$O_RATCHET" | grep -E '^xbackend (diff|ratchet):' | sed 's/^/  /'
  [ "$o_ratchet_rc" = 0 ] || { echo "  FAIL: the xbackend ratchet refuses the new manifest (rc $o_ratchet_rc)"; o_fail=1; }
  [ "$o_fail" = 0 ] || { verdict "NOT LANDABLE — the predicted oracle failed its checks; $M left detached"; exit 1; }

  O_EXPLAIN="$(ALATYR_CORPUS_EXPLAIN_CAP=400 bash scripts/corpus_manifest.sh --explain scripts/corpus.manifest "$FRESH")"
  O_PAIRS="$(sed -n 's/^pairs=//p' "$DELTA_REL" | head -n 1)"
  O_MSG="$ROOT/target/land-oracle-commit.msg"
  {
    printf 'chore(oracle): record the corpus transitions #%s predicted\n\n' "$PR"
    printf 'The corpus manifest the full gate generated on merge %s, committed byte for byte. That\n' "$(git rev-parse --short "$M")"
    printf 'walk differed from the committed manifest by exactly the %s pair(s) declared in\n' "$O_PAIRS"
    printf '%s (base %s, result %s), so this commit\n' "$DELTA_REL" "$(printf '%s' "$BASE_MANIFEST_SHA" | cut -c1-12)" "$(printf '%s' "$O_RESULT" | cut -c1-12)"
    printf 'changes no source byte and the gate on its parent is its verdict (scripts/land.sh PHASE 6a).\n\n'
    printf 'scripts/corpus_manifest.sh --explain <baseline> <new>, verbatim:\n\n'
    printf '%s\n' "$O_EXPLAIN" | sed 's/^/  /'
    printf '\nVerification: cmp against the gated run'"'"'s fresh manifest; the commit changes\n'
    printf 'scripts/corpus.manifest alone; xbackend_diff.sh --ratchet on it:\n'
    printf '%s\n' "$O_RATCHET" | grep -E '^xbackend (diff|ratchet):' | sed 's/^/  /'
    [ -n "$ISSUE" ] && printf '\nRefs #%s\n' "$ISSUE"
  } > "$O_MSG"
  cp "$FRESH" scripts/corpus.manifest
  git add scripts/corpus.manifest
  git commit --quiet --no-verify -F "$O_MSG" || die "could not create the oracle commit"
  O="$(git rev-parse HEAD)"
  message_shape_check "oracle commit $O" "$(git log -1 --format=%b "$O")" || o_fail=1
  [ "$(git rev-parse "$O^")" = "$M" ] || { echo "  FAIL: the oracle commit's parent is not the gated merge"; o_fail=1; }
  oracle_commit_paths_check "$(git diff --name-only "$M" "$O")" || o_fail=1
  git show "$O:scripts/corpus.manifest" | cmp -s - "$FRESH" || { echo "  FAIL: the committed oracle is not the fresh manifest"; o_fail=1; }
  [ "$o_fail" = 0 ] || { verdict "NOT LANDABLE — the oracle commit $O failed its shape checks"; exit 1; }
  echo "  oracle commit $O: scripts/corpus.manifest alone, byte-identical to the gated run's fresh walk"

  if [ "$DO_REWALK" = 1 ]; then
    say "PHASE 6b — determinism spot-check: one corpus re-walk on $O (not the verdict)"
    ( ulimit -c 0; nix develop -c bash scripts/corpus_manifest.sh --check ) > "$ROOT/target/land-rewalk.log" 2>&1
    rw_rc=$?
    grep -E '^corpus manifest: (rows=|match|MISMATCH|note)' "$ROOT/target/land-rewalk.log" | sed 's/^/  /'
    if [ "$rw_rc" != 0 ] || ! grep -q '^corpus manifest: match (' "$ROOT/target/land-rewalk.log"; then
      verdict "NOT LANDABLE — a second walk of the same tree did not reproduce the oracle (rc $rw_rc); the walk is not deterministic here, see target/land-rewalk.log"
      exit 1
    fi
  else
    echo "  re-walk skipped (--no-rewalk)"
  fi
  git diff --exit-code --quiet && git diff --cached --exit-code --quiet && [ "$(git rev-parse HEAD)" = "$O" ] ||
    { verdict "NOT LANDABLE — the tree moved after the oracle commit"; exit 1; }
  PUBLISH="$O"
fi

verdict "GATE GREEN on the merged tree — $PUBLISH is landable"
[ "$PUBLISH" != "$M" ] && echo "  ($PUBLISH = gated merge $M + its predicted one-file oracle commit)"
cat <<EOF

Publish EXACTLY this object. The lease is the integrator token: it fails, server-side, if main moved
after $BASE was read, and then this PR must be re-merged and re-gated.

    git push origin $PUBLISH:refs/heads/main --force-with-lease=refs/heads/main:$BASE

Afterwards, follow alatyr-integrate §5. It re-reads the branch and performs the separately
preconditioned remote-branch deletion, claim release, acceptance readback, selected snapshot cleanup,
and conservative local cleanup. Do not copy a branch-deletion command assembled from PR metadata.
EOF

if [ "$DO_PUSH" = 1 ]; then
  say "PHASE 7 — publish"
  git push origin "$PUBLISH:refs/heads/main" --force-with-lease=refs/heads/main:"$BASE" || {
    verdict "PUSH REJECTED — main moved after $BASE. Re-run: the merge must be re-gated."
    exit 1
  }
  verdict "LANDED — main is now $PUBLISH"
  echo "The selected PR snapshot $PR_REF is deliberately retained after this push."
  echo "Follow alatyr-integrate §5 for feature-branch/local worktree cleanup, claim release,"
  echo "acceptance readback, and exact snapshot cleanup; retain dirty, diverged, or ambiguous state."
fi
exit 0
