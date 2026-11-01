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
#   scripts/land.sh <pr-number> --screen
#       PHASES 0-2 only (preconditions, fetch, provenance, PR shape); merges nothing. Prints one line
#       `land-screen: pr=N head=SHA solo=yes|no link=<relation marker>` and exits 0 when the PR may be
#       merged; solo=yes when it carries an oracle file or a predicted delta, which is gated alone.
#       scripts/queue.sh (#1127) screens each queued PR this way before batching it.
#   ALATYR_LAND_EXPECT_HEAD=<sha>  refuse unless the fetched PR head is exactly <sha> (the queue's
#                                  reviewed head)
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
# A delta predicted against an older manifest (another delta PR's oracle commit landed first) is not
# refused for that alone: PHASE 2 rebases it onto BASE's manifest with `corpus_manifest.sh
# --rebase-delta` (#1264), and refuses only when a declared pair overlaps what moved, or when its rows
# do not rebuild its own result. PHASE 3 puts that rebased copy into the merge commit. Every delta PR
# edits the one `-merge` file, so PHASE 3 settles a conflict there; it also settles CHANGELOG.md when
# both sides only added `## Unreleased` bullets, or main opened a release heading there (#1312), and
# refuses every other conflict; on a clean merge too, a line the PR added that git filed under a release
# heading moves back to `## Unreleased` (#1319). The merge message says so, and the PR's branch is never rewritten. The rebased rows are a hypothesis about main's code, not
# a fact (#1215), so PHASE 3b walks the corpus alone on the merge and refuses there when the walk does
# not realise them. The gate then reads the rebased delta as the merged tree's own file, and PHASE 6a
# commits what it realised.
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
## RUN FROM A COPY (#1093). bash reads a script incrementally, seeking through the file as it runs.
## PHASE 3 merges the PR into this tree, so a PR that edits scripts/land.sh would rewrite the file
## under the interpreter and execution would resume at a byte offset into different text. So the
## script re-executes itself from a private copy under target/ before doing anything; ROOT resolves
## to the same repository root from there. The version the integrator invoked governs this landing;
## a merged change to land.sh takes effect from the next one.
land_is_private_copy() { case "$(basename "$1")" in land-run-*.sh) return 0 ;; *) return 1 ;; esac; }
if ! land_is_private_copy "$SELF"; then
  mkdir -p "$ROOT/target" || { printf 'land: cannot create %s/target for the private copy\n' "$ROOT" >&2; exit 2; }
  LAND_COPY="$ROOT/target/land-run-$$.sh"
  cp "$SELF" "$LAND_COPY" || { printf 'land: cannot copy %s to %s\n' "$SELF" "$LAND_COPY" >&2; exit 2; }
  exec "${BASH:-bash}" "$LAND_COPY" "$@"
fi
land_is_private_copy "$SELF" && trap 'rm -f "$SELF"' EXIT   # never the tracked file
cd "$ROOT" || exit 2
REPO="${ALATYR_REPO:-alatyr-programming-language/compiler}"

say()  { printf '\n=== %s\n' "$*"; }
die()  { printf 'land: %s\n' "$*" >&2; exit 2; }
verdict() { printf '\n*** %s ***\n' "$*"; }
sha256_of() { if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi; }

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

## The seed's promotion journal is append-only: never rewrite an entry to make an old hash resolve.
## Since #1130 the journal is `seed/HISTORY.md`, and `seed/VERSION` keeps only its header and the
## CURRENT SEED block. So the protected lines are every line of `seed/HISTORY.md`, plus the two
## `current-seed-*` lines and the `rs-ancestor:` line of `seed/VERSION`, which a PR never moves (a promotion is the integrator's,
## and it is landed by hand). The header prose of `seed/VERSION` is not history and may be edited.
pr_seed_version_append_only_check() { # changed-paths deleted-line-count
  printf '%s\n' "$1" | grep -qxE 'seed/(VERSION|HISTORY\.md)' || return 0
  case "${2:-0}" in ''|0) return 0 ;; esac
  echo "  REFUSE: the seed journal is append-only and this PR deletes ${2} protected line(s)."
  echo '          Protected means every line of seed/HISTORY.md (the dated promotion entries) and the'
  echo '          `current-seed-sha256`, `current-seed-version` and `rs-ancestor:` lines of seed/VERSION: rewriting them is'
  echo '          how an old hash is made to resolve. A new promotion entry is APPENDED to seed/HISTORY.md.'
  echo '          The ONE mutable line is `# spec-pin:` in seed/VERSION, which moves with the pin.'
  return 1
}

## The deletions the rule above PROTECTS, from `git diff` lines on stdin, given the file they come from.
## In seed/HISTORY.md every deleted line counts. In seed/VERSION only the two `current-seed-*` fields
## count, with the fixed `rs-ancestor:` provenance line: `# spec-pin:` is the CURRENT pin claim and moving the pin REQUIRES rewriting exactly that line
## (#1080 hit this when every deletion counted: one modified `spec-pin:` line, LAND REFUSED), and the
## header prose is description, not the journal.
pr_seed_version_protected_deletions() { # file ; deleted diff lines on stdin -> count of protected ones
  case "${1:-seed/VERSION}" in
    seed/HISTORY.md) grep -c '' ;;
    *) grep -cE '^-(current-seed-(sha256|version)|rs-ancestor):' ;;
  esac
}

## The xbackend baseline is the line the ratchet holds, and a PR that moves it blesses its own
## disagreement (#1019: `xb_ratchet` prints "do NOT raise the baseline" in prose, to a log, and
## nothing checks it). The landing moves it instead, in PHASE 6c, and only by the paths and rows the
## gate reported as newly covered — coverage added, never a disagreement on a path that had a test.
## Defined up here so the self-test, which ends in `exit`, can reach it.
pr_xbackend_baseline_edit_check() { # changed-paths -> 0 clean, 1 REFUSE
  printf '%s\n' "$1" | grep -qx "scripts/xbackend_diff.baseline" || return 0
  echo "  REFUSE: this PR edits scripts/xbackend_diff.baseline. The baseline moves at landing"
  echo "          (scripts/land.sh PHASE 6c) by exactly the newly covered paths and rows the gate"
  echo "          printed; a PR that moves it by hand is blessing its own disagreement (#1019)."
  return 1
}

## Every issue the known deviations name is OPEN (#1126 S2). The gate holds the table's consistency
## and runs with no GitHub credentials (queue.sh strips them), so the one fact it cannot see, an
## issue's state, is checked here. The table is read from the PR head with `git show`, never by running
## the PR's own scripts. A fix PR that closes an issue deletes its rows and its table line in the same
## PR, so a closed issue still in the table is a row that outlived its fix, or a fix that never came.
## Inputs: the table text and the open issue numbers, one per line. An empty open list is a failed query.
pr_deviation_issues_open_check() { # table-text open-numbers -> 0 clean, 1 REFUSE, 2 no answer
  [ -n "$1" ] || return 0
  [ -n "$2" ] || { echo "  REFUSE: the open-issue list is empty, so the known-deviation issues cannot be checked (not a pass)"; return 2; }
  local closed
  closed="$(printf '%s\n' "$1" | awk -F'\t' 'NR == FNR { O[$1] = 1; next } /^#/ || $0 == "" { next } !($1 in O) { printf " #%s", $1 }' \
    <(printf '%s\n' "$2") - )"
  [ -z "$closed" ] && return 0
  echo "  REFUSE: scripts/known-deviations.issues.tsv names issue(s) that are not open:$closed."
  echo "          The fix that closed each one deletes its rows and its table line (#1126 S2)."
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

## The predicted delta must be a prediction against the oracle this merge starts from, because a delta
## whose base is not the committed manifest is INERT, and the walk then needs a byte-for-byte match it
## cannot have. Decided here, before a 55-minute gate:
##   0  nothing to decide (no delta, a deleted one), or LIVE: predicted against this very manifest
##   1  refused: no base_sha256 at all
##   3  STALE: predicted against another manifest. Another delta PR's oracle commit makes every other
##      delta in flight stale (#1264), so the caller REBASES it (`corpus_manifest.sh --rebase-delta`)
##      and refuses only when that refuses, when a declared pair overlaps what moved.
DELTA_REL=scripts/corpus.expected-delta
pr_delta_base_check() { # changed-paths declared-base-sha|absent base-manifest-sha
  printf '%s\n' "$1" | grep -qx "$DELTA_REL" || return 0
  [ "$2" = absent ] && return 0          # the PR deletes a spent delta: nothing is declared
  [ -n "$2" ] && [ "$2" = "$3" ] && return 0
  if [ -z "$2" ]; then
    echo "  REFUSE: $DELTA_REL names no base_sha256, so it is a prediction against nothing."
    echo "          Re-emit it with scripts/corpus_manifest.sh --emit-expected; never hand-edit it."
    return 1
  fi
  echo "  predicted delta: STALE — $DELTA_REL was predicted against manifest $2,"
  echo "          but this merge starts from ${3:-<unknown>}; rebasing it onto that manifest (#1264)"
  return 3
}

## The manifest a stale delta was predicted against, found by its sha256 among the manifests of
## <revs> (tried in order) and written to <out>. Its job: `--rebase-from` checks on it that the delta's
## rows rebuild its own result there. A delta whose base is nowhere in reach cannot be checked that
## way, and is refused rather than rebased blind.
land_manifest_by_sha() { # sha256 out rev...
  local want="$1" out="$2" rev; shift 2
  for rev in "$@"; do
    git show "$rev:scripts/corpus.manifest" > "$out" 2>/dev/null || continue
    [ "$(sha256_of < "$out")" = "$want" ] && return 0
  done
  rm -f "$out"; return 1
}

## THE PRE-WALK (#1264). A rebased delta is a hypothesis, not a fact. Its rows were measured on the
## code of the PR's own base, and the rebase checks them against main's manifest, never against main's
## code. A change on main can move what the PR's own new or changed fixtures do while no row the delta
## names moves in the manifest. #1215 is the case: #1227's guard turned its new fixture's run/7 into
## run/132-134, and the four mechanically rebased ADDED rows still said run/7. The full gate catches
## that (MISPREDICTED, red), but only after ~90 minutes. So a landing that rebased its delta builds the
## merged compiler (seed -> Stage1 -> Stage2) and walks the corpus alone first: ~15 minutes on omen
## (measured on #1215: 833 s, of which the walk was 255 s at four jobs). The full gate runs only when that
## walk realises the rebased delta, and a walk that cannot answer leaves the decision to the full gate.
## A live delta goes straight to the full gate, as before: its author walked it against the manifest
## main still holds, and the landing did not rewrite it. The pre-walk is for a prediction the landing
## rewrote.
##   land_prewalk_needed: 0 run the pre-walk, 1 go straight to the full gate
land_prewalk_needed() { [ -n "$1" ]; } # rebased-from-sha|''
## What the pre-walk decided, from its exit status and log. Prints one of:
##   realised    `match by the declared delta`, exit 0: the full gate runs
##   unrealised  the walk finished and the fresh manifest is NOT the rebased delta's result: refuse now
##   unknown     anything else (a build failure, a malformed delta, a TIMED-OUT pair, an inert delta, a
##               walk that died): not a verdict on the prediction, so the full gate decides
land_prewalk_outcome() { # walk-rc walk-log
  if [ "$1" = 0 ] && grep -q '^corpus manifest: match by the declared delta' "$2" 2>/dev/null; then
    echo realised; return; fi
  ## The timeout test reads the delta report alone: the walk's own self-test banners name
  ## `compile_timeout` and `TIMED-OUT` on every run (measured on #1215's pre-walk log).
  if [ "$1" = 1 ] && grep -q '^corpus manifest: MISMATCH against the declared delta' "$2" 2>/dev/null &&
     grep -q '^corpus delta: the fresh manifest does NOT differ' "$2" &&
     ! land_prewalk_report "$2" | grep -q -E 'TIMED-OUT|_timeout/'; then
    echo unrealised; return; fi
  echo unknown
}
## The walk's delta report: from its first line to the MISMATCH verdict, nothing else of the log.
land_prewalk_report() { # walk-log
  sed -n '/^corpus delta: the fresh manifest does NOT differ/,/^corpus manifest: MISMATCH against the declared delta/p' "$1"
}

## CHANGELOG.md in PHASE 3's merge (#1312). Every PR that adds an `## Unreleased` bullet adds it at the
## same place, so after one lands the next conflicts there, and a seed promotion that opens a release
## heading under `## Unreleased` does the same. This settles exactly those shapes and refuses the rest:
## each conflict hunk must be a pure addition on both sides (an empty base), sit under `## Unreleased`,
## and have a bullet run (`- ` lines and their indented continuations) on the PR's side. Main's side is
## either a bullet run, kept first with the PR's after it, or a release heading over bullets, in which
## case the PR's run goes above it, still under `## Unreleased`. Input: `git merge-file --diff3` output.
## Writes the resolved file to stdout and `<hunks> <headings>` to <summary>; a refusal names its hunk
## on stderr and exits 1.
land_changelog_resolve() { # diff3-merged-file summary-file
  awk -v sum="$2" '
    function isbul(s) { return s ~ /^- / || s ~ /^  +[^ ]/ }
    function isrel(s) { return s ~ /^## [0-9]+\.[0-9]+\.[0-9]+([^0-9]|$)/ }
    function fail(m)  { print "CHANGELOG.md conflict hunk " h ": " m > "/dev/stderr"; bad = 1; exit 1 }
    function emit(s)  { print s; if (s ~ /^## /) sec = s }
    function resolve(   p, s, i, ob, oe, tb, te, ok) { # ok: main side without its trailing blanks
      h++
      if (nb > 0) fail("both sides rewrite existing lines; only additions are settled")
      p = 0; while (p < no && p < nt && o[p+1] == t[p+1]) { p++; emit(o[p]) }
      s = 0; while (s < no - p && s < nt - p && o[no-s] == t[nt-s]) s++
      if (sec !~ /^## Unreleased[[:space:]]*$/) fail("it sits under \"" sec "\", not ## Unreleased")
      ob = p + 1; oe = no - s; tb = p + 1; te = nt - s
      while (te >= tb && t[te] == "") te--
      if (te < tb || t[tb] !~ /^- /) fail("the PR side is not a bullet run")
      for (i = tb; i <= te; i++) if (!isbul(t[i])) fail("the PR side is not a bullet run: \"" t[i] "\"")
      while (ob <= oe && o[ob] == "") ob++
      if (ob > oe) fail("main side is empty")
      if (o[ob] ~ /^- /) {
        for (i = ob; i <= oe; i++) if (o[i] != "" && !isbul(o[i])) fail("main side is not a bullet run: \"" o[i] "\"")
        ok = oe; while (o[ok] == "") ok--
        for (i = p + 1; i <= ok; i++) emit(o[i])
        for (i = tb; i <= te; i++) emit(t[i])
        for (i = 0; i < oe - ok || i < nt - s - te; i++) emit("")
      } else if (isrel(o[ob])) {
        for (i = ob + 1; i <= oe; i++) if (o[i] != "" && !isbul(o[i])) fail("main side under its release heading is not bullets: \"" o[i] "\"")
        for (i = tb; i <= te; i++) emit(t[i])
        emit("")
        for (i = ob; i <= oe; i++) emit(o[i])
        heads++
      } else fail("main side is neither a bullet run nor a release heading: \"" o[ob] "\"")
      for (i = nt - s + 1; i <= nt; i++) emit(t[i])
    }
    st == 0 && /^<<<<<<< / { st = 1; no = 0; nb = 0; nt = 0; next }
    st == 1 && /^\|\|\|\|\|\|\| / { st = 2; next }
    st == 1 && /^=======$/ { h++; fail("no base section (not diff3 output)") }
    st == 2 && /^=======$/ { st = 3; next }
    st == 3 && /^>>>>>>> / { resolve(); st = 0; next }
    st == 1 { o[++no] = $0; next }
    st == 2 { b[++nb] = $0; next }
    st == 3 { t[++nt] = $0; next }
    { emit($0) }
    END {
      if (bad) exit 1
      if (st != 0) { print "CHANGELOG.md: an unterminated conflict hunk" > "/dev/stderr"; exit 1 }
      if (h == 0) { print "CHANGELOG.md: no conflict hunk to settle" > "/dev/stderr"; exit 1 }
      print h + 0, heads + 0 > sum
    }' "$1"
}
## Settles a conflicted CHANGELOG.md in the merge in progress from its three index stages, stages the
## result, and prints the sentence the merge message and the log carry. 1 (merge left as it was): any
## stage is missing (an add/add or a deletion), or land_changelog_resolve refused.
land_changelog_merge() {
  local d rc n hd
  d="$(git rev-parse --absolute-git-dir)/land-changelog" && rm -rf "$d" && mkdir -p "$d" || return 1
  git show :1:CHANGELOG.md > "$d/base" 2>/dev/null && git show :2:CHANGELOG.md > "$d/main" 2>/dev/null &&
    git show :3:CHANGELOG.md > "$d/pr" 2>/dev/null ||
    { echo "  CHANGELOG.md: not a content conflict (a side added or deleted the file)" >&2; rm -rf "$d"; return 1; }
  ## git merge-file writes 7-character markers, and land_changelog_resolve reads them; a version that
  ## already holds such a line would end a hunk early and pass the rest unchecked into the merge (#1312).
  if grep -Eq '^(<{7}|[|]{7}|={7}|>{7})' "$d/base" "$d/main" "$d/pr"; then
    echo "  CHANGELOG.md: a line in base, main or the PR looks like a conflict marker; settle it by hand" >&2
    rm -rf "$d"; return 1
  fi
  git merge-file -p --diff3 -L main -L base -L pr "$d/main" "$d/base" "$d/pr" > "$d/merged"; rc=$?
  if [ "$rc" -lt 0 ] || [ "$rc" -gt 127 ] || ! land_changelog_resolve "$d/merged" "$d/sum" > "$d/out"; then
    rm -rf "$d"; return 1
  fi
  cp "$d/out" CHANGELOG.md && git add -- CHANGELOG.md || { rm -rf "$d"; return 1; }
  read -r n hd < "$d/sum"; rm -rf "$d"
  printf 'CHANGELOG.md: %s conflict hunk(s) under ## Unreleased settled by scripts/land.sh (#1312):\n' "$n"
  printf "both bullet runs kept, main's first"
  [ "$hd" -gt 0 ] && printf "; in %s, main's side opened a release heading, so the PR's run stays\nunder ## Unreleased above it" "$hd"
  printf '.\n'
}

## A CLEAN CHANGELOG.md merge can misfile too (#1319): over a seed promotion that opened a release
## heading under `## Unreleased`, git puts a PR's added bullet where the old Unreleased content was,
## now under the release. This compares main's file with the merged one. Every run of lines the merge
## inserted (`diff` "a" hunks: the PR's additions) that sits under a release heading (`## X.Y.Z`) moves
## to the end of `## Unreleased`, its leading and trailing blank lines dropped. Lines under the policy
## headings above `## Unreleased` are the policy's own text and stay. A rewrite of a released line
## (a "c" hunk that adds no line) stays where it is: it edits that entry. Refused (1, stderr): a hunk
## under a release that rewrites lines and adds more, an inserted release heading, or no `## Unreleased`
## to move to. Writes the file to stdout and `<runs moved>` then each heading moved from to <summary>.
land_changelog_relocate() { # main-file merged-file summary-file
  [ -f "$1" ] && [ -f "$2" ] || return 1
  awk -v sum="$3" '
    function isrel(s) { return s ~ /^## [0-9]+\.[0-9]+\.[0-9]+([^0-9]|$)/ }
    function fail(m)  { print "CHANGELOG.md: " m > "/dev/stderr"; bad = 1; exit 1 }
    FILENAME == ARGV[1] {
      if ($0 !~ /^[0-9]+(,[0-9]+)?[acd][0-9]+(,[0-9]+)?$/) next
      match($0, /[acd]/); op = substr($0, RSTART, 1)
      nl = split(substr($0, 1, RSTART - 1), la, ","); nr = split(substr($0, RSTART + 1), ra, ",")
      del = (nl == 2) ? la[2] - la[1] + 1 : 1; r1 = ra[1] + 0; r2 = (nr == 2) ? ra[2] + 0 : r1
      if (op == "a") { run++; for (i = r1; i <= r2; i++) RUN[i] = run }
      else if (op == "c" && r2 - r1 + 1 > del) for (i = r1; i <= r2; i++) GROW[i] = 1
      next
    }
    { L[++n] = $0 }
    END {
      if (bad) exit 1
      sec = ""
      for (i = 1; i <= n; i++) {
        s = L[i]
        if (s ~ /^## /) { if ((i in RUN) && isrel(s)) fail("line " i ": the PR adds the release heading \"" s "\"; place it by hand"); sec = s; continue }
        if (!isrel(sec)) continue
        if ((i in GROW) && s != "") fail("line " i ": under \"" sec "\" the PR rewrites lines and adds more; place them by hand")
        if (i in RUN) { DROP[i] = 1; if (s != "") { HAS[RUN[i]] = 1; if (!(sec in FROM)) { FROM[sec] = 1; from[++nf] = sec } } }
      }
      for (i = 1; i <= n; i++) if ((i in DROP) && !(RUN[i] in HAS)) delete DROP[i]
      for (i = 1; i <= n; i++) if (i in DROP) {
        r = RUN[i]; if (r != last) { nruns++; last = r; lead = 1; pend = 0 }
        if (L[i] == "") { if (!lead) pend++; continue }
        for (; pend > 0; pend--) mv[++m] = ""
        lead = 0; mv[++m] = L[i]
      }
      st = 0
      for (i = 1; i <= n; i++) {
        if (i in DROP) continue
        s = L[i]
        if (st == 1 && s ~ /^## /) { flush(1); st = 2 }
        if (st == 1) { if (s == "") nb++; else { for (; nb > 0; nb--) print ""; print s; content = 1 }; continue }
        print s
        if (st == 0 && s ~ /^## Unreleased[[:space:]]*$/) { st = 1; nb = 0; content = 0 }
      }
      if (st == 1) flush(0)
      if (st == 0 && m > 0) fail("no ## Unreleased heading to move the PR'"'"'s lines under")
      print nruns + 0 > sum
      for (j = 1; j <= nf; j++) print from[j] > sum
    }
    function flush(more,   j) {
      if (m > 0 && !content) print ""
      for (j = 1; j <= m; j++) print mv[j]
      if (m > 0 && more && nb == 0) nb = 1
      for (; nb > 0; nb--) print ""
    }' <(diff "$1" "$2") "$2"
}
## Applies land_changelog_relocate to the merge in progress (index against HEAD), stages the result,
## and prints the sentence the merge message carries; prints nothing when no line moved. 1: refused.
land_changelog_place() {
  local d n
  git cat-file -e HEAD:CHANGELOG.md 2>/dev/null && git cat-file -e :CHANGELOG.md 2>/dev/null || return 0
  git diff --cached --quiet HEAD -- CHANGELOG.md && return 0
  d="$(git rev-parse --absolute-git-dir)/land-changelog-place" && rm -rf "$d" && mkdir -p "$d" || return 1
  git show HEAD:CHANGELOG.md > "$d/main" && git show :CHANGELOG.md > "$d/merged" &&
    land_changelog_relocate "$d/main" "$d/merged" "$d/sum" > "$d/out" || { rm -rf "$d"; return 1; }
  n="$(head -n 1 "$d/sum")"
  if [ "$n" -gt 0 ]; then
    cp "$d/out" CHANGELOG.md && git add -- CHANGELOG.md || { rm -rf "$d"; return 1; }
    printf 'CHANGELOG.md: %s run(s) the PR added landed under a release heading, and scripts/land.sh\nmoved them to the end of ## Unreleased (#1319). Moved from: %s.\n' \
      "$n" "$(sed 1d "$d/sum" | paste -sd ';' - | sed 's/;/; /g')"
  fi
  rm -rf "$d"
}
## Would a clean merge of <pr> into <base> file a line the PR adds under a release heading? The screen
## sends such a PR alone, where PHASE 3 moves it or refuses (#1319); the queue's batch merges never do.
land_changelog_misfiled() { # base pr
  local tree d n
  tree="$(git merge-tree --write-tree --no-messages "$1" "$2" 2>/dev/null)" || return 1
  git cat-file -e "$1:CHANGELOG.md" 2>/dev/null && git cat-file -e "$tree:CHANGELOG.md" 2>/dev/null || return 1
  d="$(git rev-parse --absolute-git-dir)/land-changelog-screen" && rm -rf "$d" && mkdir -p "$d" || return 1
  git show "$1:CHANGELOG.md" > "$d/main" && git show "$tree:CHANGELOG.md" > "$d/merged" &&
    land_changelog_relocate "$d/main" "$d/merged" "$d/sum" > /dev/null 2>&1 || { rm -rf "$d"; return 0; }
  n="$(head -n 1 "$d/sum")"; rm -rf "$d"; [ "${n:-0}" -gt 0 ]
}

## Does merging <pr> into <base> conflict in CHANGELOG.md and, besides it, at most in the delta file?
## The screen's question: such a PR is landed alone, where PHASE 3 settles those two (#1312).
land_changelog_only_conflict() { # base pr
  local out rc
  out="$(git merge-tree --write-tree --name-only --no-messages "$1" "$2" 2>/dev/null)"; rc=$?
  [ "$rc" = 1 ] || return 1
  out="$(printf '%s\n' "$out" | sed 1d | sed '/^$/d')"
  printf '%s\n' "$out" | grep -qx CHANGELOG.md || return 1
  [ -z "$(printf '%s\n' "$out" | grep -vx -e CHANGELOG.md -e "$DELTA_REL")" ]
}

## PHASE 3's merge. Every delta PR edits the ONE file scripts/corpus.expected-delta, and .gitattributes
## marks it `-merge`, so after any delta PR lands, every other one conflicts on it, whatever else it
## does. <landing-delta> is the prediction this landing gates (the PR's own when it is live, its
## rebase when it was stale), and the merge carries it: on a conflict there it takes that side, and on a
## clean merge whose copy differs, it replaces that copy. A conflicted CHANGELOG.md is settled by
## land_changelog_merge, or refused (#1312). Any other conflicted path aborts the merge, as before.
## Then, conflict or not, land_changelog_place moves a line the PR added under a release heading to
## `## Unreleased`, or refuses (#1319).
## <note> goes into the merge message whenever the delta was written, so the merge commit says why its
## delta differs from the PR's; each CHANGELOG sentence goes there whenever that file was settled or moved.
##   0  merged (HEAD is the merge commit)    1  a conflict this does not resolve (merge aborted)
land_merge_pr() { # pr-ref subject link landing-delta|'' note
  local ref="$1" subj="$2" link="$3" ld="$4" note="$5" unmerged wrote=0 msg p clnote='' plnote
  if ! git merge --no-ff --no-commit --no-verify "$ref" >/dev/null 2>&1; then
    unmerged="$(git diff --name-only --diff-filter=U)"
    [ -n "$unmerged" ] || { git merge --abort 2>/dev/null; return 1; }
    while IFS= read -r -d '' p; do  # NUL-separated and unexpanded: the case is the only guard
      case "$p" in
        "$DELTA_REL") [ -n "$ld" ] || { git merge --abort 2>/dev/null; return 1; } ;;
        CHANGELOG.md) ;;
        *) git merge --abort 2>/dev/null; return 1 ;;
      esac
    done < <(git diff -z --name-only --diff-filter=U)
    if printf '%s\n' "$unmerged" | grep -qx CHANGELOG.md; then
      clnote="$(land_changelog_merge)" || {
        echo "  CHANGELOG.md conflicts in a shape scripts/land.sh does not settle (above)"
        git merge --abort 2>/dev/null; return 1; }
      printf '%s\n' "$clnote" | sed 's/^/  /'
    fi
  fi
  plnote="$(land_changelog_place)" || {
    echo "  CHANGELOG.md: the PR adds lines under a release heading in a shape scripts/land.sh does not move (above)"
    git merge --abort 2>/dev/null; return 1; }
  [ -z "$plnote" ] || printf '%s\n' "$plnote" | sed 's/^/  /'
  if [ -n "$ld" ] && { [ -n "$(git diff --name-only --diff-filter=U)" ] || ! cmp -s "$ld" "$DELTA_REL"; }; then
    cp "$ld" "$DELTA_REL" && git add -- "$DELTA_REL" || { git merge --abort 2>/dev/null; return 1; }
    wrote=1
  fi
  msg="$subj"
  [ "$wrote" = 1 ] && [ -n "$note" ] && msg="$msg

$note"
  [ -n "$clnote" ] && msg="$msg

$clnote"
  [ -n "$plnote" ] && msg="$msg

$plnote"
  [ -n "$link" ] && msg="$msg

$link"
  git commit --quiet --no-verify -m "$msg" >/dev/null 2>&1 || { git merge --abort 2>/dev/null; return 1; }
  [ -z "$ld" ] || git show "HEAD:$DELTA_REL" | cmp -s - "$ld" || return 1
  return 0
}

## The oracle commit PHASE 6a makes changes the corpus manifest and NOTHING else — the whole argument
## that its source tree was already gated rests on that set being exactly one path.
oracle_commit_paths_check() { # changed-paths-of-the-oracle-commit
  [ "$1" = scripts/corpus.manifest ] && return 0
  echo "  REFUSE: the oracle commit changes {$(printf '%s' "$1" | tr '\n' ' ')} — it must change exactly"
  echo "          {scripts/corpus.manifest}, or the gate on its parent is not a verdict on it."
  return 1
}

## ATTRIBUTION. The decider and the pattern live in `scripts/attribution.sh`, which the pre-commit
## hook sources too — one definition, so the hook and the landing gate can never disagree about the
## same message. The rule, its reason and its scope boundary are documented there.
source "$ROOT/scripts/attribution.sh"

## PROVENANCE. `main` is advanced only over commits that came through a pull request: the merge this
## script (or a batch) makes, plus the integrator's own TAIL on top of such a merge — a one-oracle
## commit (the manifest, optionally with the xbackend ratchet line it moves) or a reseed. A direct push
## of anything else was never gated as a landing, and building the next merge on it would quietly make
## the next gate its first one. One step of the first-parent walk from origin/main's tip:
##   0  a merge whose second parent is the head of a PR merged into main — provenance established
##   3  an integrator tail commit — keep walking to its first parent
##   1  anything else — refuse
LAND_TAIL_ORACLE_RE='^(scripts/corpus\.manifest|scripts/idiom\.baseline|scripts/needle\.baseline|scripts/xbackend_diff\.baseline)$'
LAND_TAIL_RESEED_RE='^(package\.al|seed/alatyr|seed/VERSION|seed/HISTORY\.md|scripts/package_cli_test\.sh|CHANGELOG\.md)$'
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
LAND_SELFTEST_EXPECTED=124  # the exact count run, compared with -ne; +2 #1106, +4 #1091, +4 #1090, +3 #1089, +5 #1093, +2 #1130, +9 #1264, +9 #1264 pre-walk, +4 #1126 S2, +10 #1312, +5 #1319
## Can this checkout push? An SSH remote authenticates without a credential helper; an HTTPS one needs
## either a helper or a token in the environment. Empty answers on all three means the push at PHASE 7
## would stall waiting for a prompt that has no terminal to appear on (#1085, ~30 minutes of nothing).
## Defined ABOVE `land_shape_self_test`, which calls it: bash defines a function when execution reaches
## its definition, and the self-test runs before the PHASE 0 block that uses it for real.
## The `+` is load-bearing (#1091). The PR ref caches what the remote says `refs/pull/N/head` is, and
## GitHub moves that ref BACKWARDS on every rebase and force-push — which PHASE 3's own conflict verdict
## asks for. Without `+` the second landing attempt of any rebased PR dies as "fetch failed". The ref is
## only a local cache: PHASE 1 compares what it fetched with the head GitHub reports before using it.
land_fetch_pr_ref() { # remote pr-number local-ref -> git fetch's status
  git fetch --quiet "$1" main "+refs/pull/$2/head:$3"
}

land_push_capability_ok() { # remote-url credential-helper token -> 0 can, 1 cannot
  case "$1" in
    git@*|ssh://*) return 0 ;;
    https://*|http://*|"" ) : ;;
    * ) return 0 ;;
  esac
  [ -n "$2" ] && return 0
  [ -n "$3" ] && return 0
  return 1
}

## Is the integration checkout dirty for the purpose of a gate? (#1090) Input: `git status --porcelain`.
## Every tracked or staged change counts, and so does every untracked path, with ONE exception: the
## root-level `.worktrees/` directory, which holds other checkouts (on omen a nested set of lane
## worktrees sits there) and which no gate stage reads: the walkers use `git ls-files` or are limited to
## `src/`, `lib/` and `test/`. The match is exact, so a lookalike such as `.worktrees.bak/` still counts.
## Anything else untracked
## still refuses — a stray `package.al` or fixture is exactly the hazard AGENTS.md records.
land_tree_dirty() { # porcelain-text -> prints offending lines; 0 dirty, 1 clean
  local rest
  rest="$(printf '%s\n' "$1" | grep -v -x -e '' -e '?? .worktrees/' || true)"
  [ -n "$rest" ] || return 1
  printf '%s\n' "$rest"
  return 0
}

## Which credential helper would git use for this remote? (#1089) `gh auth setup-git` writes the
## HOST-SPECIFIC key `credential.https://github.com.helper`, which is what git consults for an HTTPS
## remote; reading only the generic `credential.helper` refused a checkout that could push. git's own
## URL matching answers the question the push will ask, generic and host-specific keys alike.
land_cred_helper_for() { # remote-url -> prints the helper git would use, or nothing
  git config --get-urlmatch credential.helper "$1" 2>/dev/null || true
}

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
  case "$out" in *'deletes 4 protected line(s)'*) _ck 0 x ;; *) _ck 1 append-only-did-not-name-the-deletion-count ;; esac
  # #1106 · the refusal exists to tell the integrator WHICH lines are protected, so it has to
  # NAME them. They were written in backticks inside a double-quoted echo, which bash runs as
  # command substitution: `current-seed-*` became "command not found" and `# spec-pin:` — a
  # comment, exit 0, empty output — vanished, leaving "The ONE mutable line is" with nothing
  # after it. A refusal that names no field cannot be acted on, and the existing checks above
  # passed the whole time because they only ever looked for the count.
  case "$out" in *'current-seed-sha256'*) _ck 0 x ;; *) _ck 1 append-only-refusal-did-not-name-current-seed-sha256 ;; esac
  case "$out" in *'ONE mutable line is `# spec-pin:`'*) _ck 0 x ;; *) _ck 1 append-only-refusal-ate-the-mutable-line-name ;; esac
  pr_seed_version_append_only_check seed/VERSION 0 >/dev/null 2>&1
  _ck $? append-only-refused-a-pure-append
  pr_seed_version_append_only_check src/lower.al 4 >/dev/null 2>&1
  _ck $? append-only-fired-on-a-PR-that-does-not-touch-seed/VERSION
  ## The xbackend baseline: a PR never moves the line the ratchet holds (#1019).
  out="$(pr_xbackend_baseline_edit_check "src/lower.al
test/issue502_deref_inferred_str_operand.al" 2>&1)"; rc=$?
  [ "$rc" = 0 ]; _ck $? "baseline-edit-allowed-a-PR-that-touches-no-baseline"
  out="$(pr_xbackend_baseline_edit_check "scripts/xbackend_diff.baseline
src/lower.al" 2>&1)"; rc=$?
  [ "$rc" = 1 ]; _ck $? "baseline-edit-refused-a-PR-that-moved-the-ratchet-line"
  case "$out" in *'#1019'*) _ck 0 x ;; *) _ck 1 baseline-edit-did-not-name-1019 ;; esac
  ## A path that merely contains the name is not the file (`grep -qx`, not a substring match).
  pr_xbackend_baseline_edit_check "scripts/xbackend_diff.baseline.bak
docs/xbackend_diff.baseline-notes.md" >/dev/null 2>&1
  _ck $? "baseline-edit-allowed-a-lookalike-path"
  ## The known-deviation issues are open (#1126 S2).
  _dt="$(printf '# issue\trule\tdifference\trows|none\n11\tr\td\trows\n14\tr\td\tnone')"
  pr_deviation_issues_open_check "$_dt" "$(printf '11\n14\n99')" >/dev/null 2>&1
  _ck $? "deviation-issues-refused-a-table-of-open-issues"
  out="$(pr_deviation_issues_open_check "$_dt" "$(printf '11\n99')" 2>&1)"; rc=$?
  [ "$rc" = 1 ]; _ck $? "deviation-issues-allowed-a-closed-issue"
  case "$out" in *'#14.'*) _ck 0 x ;; *) _ck 1 deviation-issues-did-not-name-the-closed-one ;; esac
  pr_deviation_issues_open_check "$_dt" "" >/dev/null 2>&1; [ "$?" = 2 ]
  _ck $? "deviation-issues-took-an-empty-answer-for-a-pass"

  # ---- 3b · the ONE mutable line: `# spec-pin:` moves, the journal does not. ----------------
  # A pin move rewrites exactly one line and `git diff` spells that as a deletion. The counter
  # must not count it, or the rule refuses the change its own target file mandates (#1080).
  [ "$(printf '%s\n' '-# spec-pin: 1.1.0 (tag v1.1.0, spec commit 65a0c9b)' |
      pr_seed_version_protected_deletions)" = 0 ]
  _ck $? spec-pin-modification-counted-as-a-protected-deletion
  [ "$(printf '%s\n' '-current-seed-version: 0.2.17' |
      pr_seed_version_protected_deletions)" = 1 ]
  _ck $? spec-pin-exemption-ate-a-seed-version-deletion
  [ "$(printf '%s\n' '-# Self-promoted 2026-08-19 — nested enum and Slice(T) payload construction' |
      pr_seed_version_protected_deletions seed/HISTORY.md)" = 1 ]
  _ck $? journal-deletion-from-seed/HISTORY.md-not-counted
  ## #1130: the journal is a file of its own, and every line of it is protected — the spec-pin
  ## exemption is a property of seed/VERSION's CURRENT SEED block, never of an old entry.
  [ "$(printf '%s\n' '-# spec-pin: 1.1.0 (tag v1.1.0, spec commit 65a0c9b)' |
      pr_seed_version_protected_deletions seed/HISTORY.md)" = 1 ]
  _ck $? spec-pin-exemption-leaked-into-seed/HISTORY.md
  pr_seed_version_append_only_check seed/HISTORY.md 1 >/dev/null 2>&1; [ $? = 1 ]
  _ck $? append-only-allowed-a-deletion-from-seed/HISTORY.md
  [ "$(printf '%s\n%s\n' '-# spec-pin: 1.1.0 (tag v1.1.0, spec commit 65a0c9b)' \
      '-current-seed-sha256: ce7dca80b820918d80a0fab5c18460d74dd23d370700392558cb853e30e9dd0c' |
      pr_seed_version_protected_deletions)" = 1 ]
  _ck $? spec-pin-exemption-hid-an-unrelated-deletion
  ## seed/VERSION's header prose is description, not the journal, since #1130 moved the entries out.
  [ "$(printf '%s\n' '-# a plain comment line' | pr_seed_version_protected_deletions seed/VERSION)" = 0 ]
  _ck $? seed/VERSION-header-prose-counted-as-journal

  # ---- push capability: the PHASE 7 stall, caught in PHASE 0 (#1085). ------------------
  # Both directions, so the probe cannot pass by always answering either way.
  # #1090 · the dirt check tolerates the root `.worktrees/` and nothing else.
  land_tree_dirty "?? .worktrees/" >/dev/null; [ $? = 1 ]; _ck $? dirty-check-refused-the-root-worktrees-dir
  land_tree_dirty "$(printf '%s\n%s' '?? .worktrees/' '?? package.al')" >/dev/null; _ck $? dirty-check-missed-a-stray-file-beside-worktrees
  land_tree_dirty " M src/lower.al" >/dev/null; _ck $? dirty-check-missed-a-tracked-edit
  land_tree_dirty "?? .worktrees.bak/" >/dev/null; _ck $? dirty-check-tolerated-a-lookalike-of-worktrees
  # #1093 · only the private copy under target/ runs the procedure; the tracked file re-executes.
  land_is_private_copy /r/target/land-run-123.sh; _ck $? private-copy-not-recognised
  land_is_private_copy /r/scripts/land.sh; [ $? = 1 ]; _ck $? tracked-script-taken-for-a-private-copy
  # …and this very run is such a copy (fails if the re-exec is gone), and a run through the tracked
  # file leaves no copy behind (fails if the EXIT trap is gone). The usage path exits 2 at once.
  land_is_private_copy "$SELF"; _ck $? self-test-not-running-from-a-private-copy
  local before after
  before="$(ls "$ROOT"/target/land-run-*.sh 2>/dev/null | sort)"
  bash "$ROOT/scripts/land.sh" x >/dev/null 2>&1; [ $? = 2 ]; _ck $? usage-path-did-not-exit-2
  after="$(ls "$ROOT"/target/land-run-*.sh 2>/dev/null | sort)"
  [ "$before" = "$after" ]; _ck $? private-copy-left-behind-after-a-run
  # #1089 · the helper git would use for the remote. Configured as `gh auth setup-git` writes it (an
  # empty reset, then the gh helper, on the HOST-SPECIFIC key), with the machine's own global and
  # system config shut out, so a generic helper elsewhere cannot make the answer right by accident.
  git init -q "$st/cred" >/dev/null 2>&1
  git -C "$st/cred" config --add credential.https://github.com.helper ''
  git -C "$st/cred" config --add credential.https://github.com.helper '!gh auth git-credential'
  [ "$(cd "$st/cred" && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 land_cred_helper_for https://github.com/o/r.git)" = '!gh auth git-credential' ]
  _ck $? cred-helper-missed-the-host-specific-key
  [ -z "$(cd "$st/cred" && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 land_cred_helper_for https://example.org/o/r.git)" ]; _ck $? cred-helper-applied-another-hosts-key
  [ "$(cd "$st/cred" && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 land_cred_helper_for https://user@github.com/o/r.git)" = '!gh auth git-credential' ]
  _ck $? cred-helper-missed-a-remote-url-with-a-user
  land_push_capability_ok "git@github.com:o/r.git" "" ""; _ck $? push-capability-ssh-needs-no-helper
  land_push_capability_ok "ssh://git@github.com/o/r" "" ""; _ck $? push-capability-ssh-url-needs-no-helper
  land_push_capability_ok "https://github.com/o/r" "store" ""; _ck $? push-capability-https-with-helper
  land_push_capability_ok "https://github.com/o/r" "" "ghp_token"; _ck $? push-capability-https-with-token
  land_push_capability_ok "https://github.com/o/r" "" ""; [ $? = 1 ]
  _ck $? push-capability-https-without-helper-or-token-was-accepted
  # #1091 · a PR ref that moved BACKWARDS on the remote (a rebase) is fetched again, not refused.
  local fo="$st/fetch-origin.git" fc="$st/fetch-clone" p1 p2
  git init -q --bare "$fo" && git init -q "$fc" &&
    git -C "$fc" -c user.name=t -c user.email=t@t commit -q --allow-empty -m one &&
    git -C "$fc" -c user.name=t -c user.email=t@t commit -q --allow-empty -m two &&
    git -C "$fc" push -q "$fo" HEAD:refs/heads/main HEAD:refs/pull/7/head &&
    git -C "$fc" remote add origin "$fo"; _ck $? fetch-fixture-could-not-be-built
  ( cd "$fc" && land_fetch_pr_ref origin 7 refs/remotes/pr/7 ); _ck $? fetch-pr-ref-failed-on-a-first-fetch
  p1="$(git -C "$fc" rev-parse HEAD~1)"
  git -C "$fo" update-ref refs/pull/7/head "$p1"
  ( cd "$fc" && land_fetch_pr_ref origin 7 refs/remotes/pr/7 ) 2>/dev/null; _ck $? fetch-pr-ref-refused-a-ref-that-moved-backwards
  p2="$(git -C "$fc" rev-parse refs/remotes/pr/7 2>/dev/null)"
  [ "$p2" = "$p1" ]; _ck $? fetch-pr-ref-kept-the-stale-head

  # ---- 4 · an oracle commit touches that oracle alone. -------------------------------------
  out="$(pr_oracle_commit_isolation_check scripts/corpus.manifest deadbeef 2 2>&1)"
  [ $? = 1 ]; _ck $? oracle-commit-allowed-a-commit-carrying-two-other-files
  case "$out" in *deadbeef*'AND 2 other file(s)'*) _ck 0 x ;;
                 *) _ck 1 oracle-commit-did-not-name-the-commit-and-the-count ;; esac
  pr_oracle_commit_isolation_check scripts/corpus.manifest deadbeef 0 >/dev/null 2>&1
  _ck $? oracle-commit-refused-a-one-file-oracle-commit

  # ---- 5 · the predicted delta's base, checked before the gate. ----------------------------
  #     A stale delta is neither passed as live nor refused outright: it is handed to the rebase (3).
  out="$(pr_delta_base_check "$(printf '%s\n%s' src/lower.al "$DELTA_REL")" aaaa bbbb 2>&1)"
  [ $? = 3 ]; _ck $? delta-base-did-not-send-a-stale-delta-to-the-rebase
  case "$out" in *'predicted against manifest aaaa'*'starts from bbbb'*) _ck 0 x ;;
                 *) _ck 1 delta-base-did-not-name-both-manifests ;; esac
  case "$out" in *REFUSE*) _ck 1 delta-base-refused-a-stale-delta-before-the-rebase-decided ;; *) _ck 0 x ;; esac
  pr_delta_base_check "$(printf '%s\n%s' src/lower.al "$DELTA_REL")" bbbb bbbb >/dev/null 2>&1
  _ck $? delta-base-refused-a-delta-predicted-against-this-merge-base
  pr_delta_base_check "$(printf '%s\n%s' src/lower.al "$DELTA_REL")" '' bbbb >/dev/null 2>&1
  [ $? = 1 ]; _ck $? delta-base-allowed-a-delta-with-no-base

  # ---- 5b · PHASE 3's merge on a real repository: the delta file is the one conflict it settles. --
  #      main and the PR both changed scripts/corpus.expected-delta (`-merge`, as in this repository).
  local g="$st/git" lb
  ( set -e
    git init --quiet -b b0 "$g"; cd "$g"
    git config user.name t; git config user.email t@t; git config commit.gpgsign false; git config core.hooksPath /dev/null
    mkdir scripts; printf '%s -merge\n' "$DELTA_REL" > .gitattributes
    echo spent-0 > "$DELTA_REL"; echo x0 > x; echo m0 > scripts/corpus.manifest
    git add -A; git commit --quiet -m base
    git switch --quiet -c pr; echo pr-delta > "$DELTA_REL"; echo y > y; git add -A; git commit --quiet -m pr
    git switch --quiet -c prx b0; echo pr-delta > "$DELTA_REL"; echo x-pr > x; git add -A; git commit --quiet -m prx
    git switch --quiet -c prc b0; echo y > y; git add -A; git commit --quiet -m prc
    git switch --quiet -c trunk b0; echo spent-1 > "$DELTA_REL"; echo x-main > x; echo m1 > scripts/corpus.manifest
    git add -A; git commit --quiet -m main ) >/dev/null 2>&1
  _ck $? selftest-could-not-build-the-merge-repository
  echo rebased-delta > "$st/ld"
  ( cd "$g" && git switch --quiet --detach trunk &&
    land_merge_pr pr 'merge #1: pr' 'Closes #9' "$st/ld" 'NOTE: rebased' &&
    [ "$(git rev-list --parents -n 1 HEAD | wc -w | tr -d ' ')" = 3 ] &&
    [ "$(git show "HEAD:$DELTA_REL")" = rebased-delta ] && [ "$(git show HEAD:y)" = y ] &&
    [ "$(git show HEAD:x)" = x-main ] && [ "$(git log -1 --format=%B HEAD)" = "$(printf 'merge #1: pr\n\nNOTE: rebased\n\nCloses #9')" ] &&
    [ "$(git show pr:"$DELTA_REL")" = pr-delta ] ) >/dev/null 2>&1
  _ck $? merge-did-not-settle-the-delta-conflict-with-the-landing-delta
  ( cd "$g" && git switch --quiet --detach trunk && lb="$(git rev-parse HEAD)" &&
    ! land_merge_pr pr 'merge #1: pr' '' '' '' &&
    [ "$(git rev-parse HEAD)" = "$lb" ] && ! git rev-parse -q --verify MERGE_HEAD ) >/dev/null 2>&1
  _ck $? merge-settled-a-delta-conflict-with-no-landing-delta
  ( cd "$g" && git switch --quiet --detach trunk && lb="$(git rev-parse HEAD)" &&
    ! land_merge_pr prx 'merge #2: prx' '' "$st/ld" 'NOTE' &&
    [ "$(git rev-parse HEAD)" = "$lb" ] && [ -z "$(git status --porcelain --untracked-files=no)" ] ) >/dev/null 2>&1
  _ck $? merge-settled-a-conflict-in-another-file-beside-the-delta
  ( cd "$g" && git switch --quiet --detach trunk &&
    land_merge_pr prc 'merge #3: prc' '' "$st/ld" 'NOTE: rebased' &&
    [ "$(git show "HEAD:$DELTA_REL")" = rebased-delta ] && git log -1 --format=%B HEAD | grep -qx 'NOTE: rebased' ) >/dev/null 2>&1
  _ck $? merge-left-a-stale-delta-on-a-clean-merge
  ( cd "$g" && git switch --quiet --detach trunk &&
    land_merge_pr prc 'merge #4: prc' '' '' 'NOTE' &&
    [ "$(git show "HEAD:$DELTA_REL")" = spent-1 ] && ! git log -1 --format=%B HEAD | grep -q NOTE ) >/dev/null 2>&1
  _ck $? merge-touched-the-delta-of-a-PR-that-declares-none
  # …and the old-base finder: by sha256, among the revisions given, or nothing.
  ( cd "$g" && land_manifest_by_sha "$(printf 'm0\n' | sha256_of)" "$st/ob" trunk b0 && [ "$(cat "$st/ob")" = m0 ] ) >/dev/null 2>&1
  _ck $? old-base-finder-missed-a-manifest-in-reach
  ( cd "$g" && ! land_manifest_by_sha "$(printf 'zz\n' | sha256_of)" "$st/ob2" trunk b0 && [ ! -e "$st/ob2" ] ) >/dev/null 2>&1
  _ck $? old-base-finder-invented-a-manifest
  pr_delta_base_check src/lower.al aaaa bbbb >/dev/null 2>&1
  _ck $? delta-base-fired-on-a-PR-that-does-not-carry-a-delta
  pr_delta_base_check "$DELTA_REL" absent bbbb >/dev/null 2>&1
  _ck $? delta-base-refused-the-deletion-of-a-spent-delta

  # ---- 5d · PHASE 3's merge settles CHANGELOG.md beside the delta, and refuses every other shape
  #      (#1312). d1 and d2 are two delta PRs off one base, each with an `## Unreleased` bullet.
  local gc="$st/gc" cb cw ct
  ( set -e
    git init --quiet -b b0 "$gc"; cd "$gc"
    git config user.name t; git config user.email t@t; git config commit.gpgsign false; git config core.hooksPath /dev/null
    mkdir scripts; printf '%s -merge\n' "$DELTA_REL" > .gitattributes
    printf '# C\n\n## Unreleased\n\n## 0.1.0 — d\n\n- old\n' > CHANGELOG.md
    echo spent-0 > "$DELTA_REL"; echo src-0 > src; git add -A; git commit --quiet -m base
    unrel() { ADD="$1" awk '{ print } /^## Unreleased$/ { getline; print; printf "%s\n", ENVIRON["ADD"] }' CHANGELOG.md > c.tmp; mv c.tmp CHANGELOG.md; }
    git switch --quiet -c d1 b0; echo d1-delta > "$DELTA_REL"; echo src-1 > src; unrel '- one
  cont
'; git add -A; git commit --quiet -m d1
    git switch --quiet -c d2 b0; echo d2-delta > "$DELTA_REL"; echo two > two; unrel '- two
'; git add -A; git commit --quiet -m d2
    git switch --quiet -c sx b0; echo src-x > src; unrel '- six
'; git add -A; git commit --quiet -m sx
    git switch --quiet -c bad b0; unrel 'Some prose.
'; git add -A; git commit --quiet -m bad
    mk7='>>>>>>''>'  # split so that the file itself holds no marker line for git diff --check
    git switch --quiet -c mk b0; unrel "- pr one
$mk7 pr
Not a bullet.
## 9.9.9 fake
"; git add -A; git commit --quiet -m mk
    git switch --quiet -c rw b0; sed 's/^- old$/- old (pr)/' CHANGELOG.md > c.tmp; mv c.tmp CHANGELOG.md; git commit --quiet -am rw
  ) >/dev/null 2>&1
  _ck $? selftest-could-not-build-the-changelog-repository
  echo d1-delta > "$st/ld1"; echo d2-delta > "$st/ld2"
  ( cd "$gc" && git switch --quiet --detach b0 && land_merge_pr d1 'merge #1: d1' '' "$st/ld1" 'NOTE' &&
    git branch t1 && git switch --quiet -c tr t1 &&
    sed 's/^- old$/- old (main)/' CHANGELOG.md > c.tmp && mv c.tmp CHANGELOG.md && git commit --quiet -am reword &&
    git switch --quiet -c tp t1 &&
    awk '/^## Unreleased$/ { print; print ""; print "## 0.2.0 — e"; next } { print }' CHANGELOG.md > c.tmp &&
    mv c.tmp CHANGELOG.md && git commit --quiet -am promote ) >/dev/null 2>&1
  _ck $? changelog-selftest-first-delta-PR-did-not-land
  ( cd "$gc" && git switch --quiet --detach t1 &&
    land_merge_pr d2 'merge #2: d2' 'Closes #8' "$st/ld2" 'NOTE: d2' &&
    [ "$(git show "HEAD:$DELTA_REL")" = d2-delta ] && [ "$(git show HEAD:two)" = two ] && [ "$(git show HEAD:src)" = src-1 ] &&
    [ "$(git show HEAD:CHANGELOG.md | tr '\n' '|')" = '# C||## Unreleased||- one|  cont|- two||## 0.1.0 — d||- old|' ] &&
    [ "$(git log -1 --format=%B HEAD)" = "$(printf '%s\n\n%s\n\n%s\n%s\n\n%s' 'merge #2: d2' 'NOTE: d2' \
      'CHANGELOG.md: 1 conflict hunk(s) under ## Unreleased settled by scripts/land.sh (#1312):' \
      "both bullet runs kept, main's first." 'Closes #8')" ] ) >/dev/null 2>&1
  _ck $? second-delta-PR-did-not-land-after-the-first-without-a-rebase
  ( cd "$gc" && git switch --quiet --detach tp &&
    land_merge_pr d2 'merge #2: d2' '' "$st/ld2" 'NOTE' &&
    [ "$(git show HEAD:CHANGELOG.md | tr '\n' '|')" = '# C||## Unreleased||- two||## 0.2.0 — e||- one|  cont||## 0.1.0 — d||- old|' ] &&
    git log -1 --format=%B HEAD | grep -q 'opened a release heading' ) >/dev/null 2>&1
  _ck $? changelog-run-not-kept-under-Unreleased-above-a-release-main-opened
  for lb in 'sx source-file-conflict-beside-the-changelog t1' 'bad changelog-paragraph-that-is-no-bullet t1' \
            'rw changelog-line-both-sides-rewrote tr' 'mk changelog-whose-PR-side-holds-a-conflict-marker-line t1'; do
    read -r cb cw ct <<< "$lb"
    ( cd "$gc" && git switch --quiet --detach "$ct" && b="$(git rev-parse HEAD)" &&
      ! land_merge_pr "$cb" "merge: $cb" '' '' '' && [ "$(git rev-parse HEAD)" = "$b" ] &&
      ! git rev-parse -q --verify MERGE_HEAD && [ -z "$(git status --porcelain --untracked-files=no)" ] ) >/dev/null 2>&1
    _ck $? "merge-settled-a-$cw"
  done
  ( cd "$gc" && land_changelog_only_conflict t1 d2 ) >/dev/null 2>&1; _ck $? screen-missed-a-changelog-only-conflict
  ( cd "$gc" && ! land_changelog_only_conflict t1 sx && ! land_changelog_only_conflict b0 d2 ) >/dev/null 2>&1
  _ck $? screen-sent-alone-a-source-conflict-or-a-clean-merge

  # ---- 5e · a CLEAN CHANGELOG.md merge over a promotion still files the PR's bullet under
  #      `## Unreleased` (#1319). u0 has one Unreleased bullet; ua adds one below it; up promotes u0's
  #      bullet into 0.2.0. Git merges ua over up cleanly, with `- b` under 0.2.0.
  local gu="$st/gu"
  ( set -e
    git init --quiet -b u0 "$gu"; cd "$gu"
    git config user.name t; git config user.email t@t; git config commit.gpgsign false; git config core.hooksPath /dev/null
    printf '# C\n\n## Policy\n\ntext\n\n## Unreleased\n\n- a\n\n## 0.1.0 — d\n\n- old\n' > CHANGELOG.md
    git add -A; git commit --quiet -m base
    git switch --quiet -c ua u0; sed 's/^- a$/- a\
- b/' CHANGELOG.md > c.tmp; mv c.tmp CHANGELOG.md; git commit --quiet -am ua
    git switch --quiet -c uw u0; sed 's/^- old$/- old (fixed)/; s/^text$/text, edited/' CHANGELOG.md > c.tmp; mv c.tmp CHANGELOG.md; git commit --quiet -am uw
    git switch --quiet -c ug u0; sed 's/^- old$/- old (fixed)\
- more/' CHANGELOG.md > c.tmp; mv c.tmp CHANGELOG.md; git commit --quiet -am ug
    git switch --quiet -c up u0
    awk '/^## Unreleased$/ { print; print ""; print "## 0.2.0 — e"; next } { print }' CHANGELOG.md > c.tmp
    mv c.tmp CHANGELOG.md; git commit --quiet -am promote
    [ "$(git merge-tree --write-tree up ua | wc -l | tr -d ' ')" = 1 ] ) >/dev/null 2>&1
  _ck $? selftest-could-not-build-a-clean-changelog-merge-over-a-promotion
  ( cd "$gu" && git switch --quiet --detach up && land_merge_pr ua 'merge #5: ua' '' '' '' &&
    [ "$(git show HEAD:CHANGELOG.md | tr '\n' '|')" = '# C||## Policy||text||## Unreleased||- b||## 0.2.0 — e||- a||## 0.1.0 — d||- old|' ] &&
    git log -1 --format=%B HEAD | grep -q 'moved them to the end of ## Unreleased (#1319). Moved from: ## 0.2.0 — e.' ) >/dev/null 2>&1
  _ck $? clean-merge-filed-the-PR-bullet-under-the-release-it-merged-over
  ( cd "$gu" && git switch --quiet --detach u0 && land_merge_pr ua 'merge #6: ua' '' '' '' &&
    [ "$(git show HEAD:CHANGELOG.md | tr '\n' '|')" = '# C||## Policy||text||## Unreleased||- a|- b||## 0.1.0 — d||- old|' ] &&
    ! git log -1 --format=%B HEAD | grep -q '#1319' &&
    git switch --quiet --detach up && land_merge_pr uw 'merge #7: uw' '' '' '' &&
    [ "$(git show HEAD:CHANGELOG.md | tr '\n' '|')" = '# C||## Policy||text, edited||## Unreleased||## 0.2.0 — e||- a||## 0.1.0 — d||- old (fixed)|' ] &&
    ! git log -1 --format=%B HEAD | grep -q '#1319' ) >/dev/null 2>&1
  _ck $? changelog-move-touched-an-Unreleased-bullet-a-policy-edit-or-a-released-line-rewrite
  ( cd "$gu" && git switch --quiet --detach up && b="$(git rev-parse HEAD)" && ! land_merge_pr ug 'merge #8: ug' '' '' '' &&
    [ "$(git rev-parse HEAD)" = "$b" ] && ! git rev-parse -q --verify MERGE_HEAD &&
    [ -z "$(git status --porcelain --untracked-files=no)" ] ) >/dev/null 2>&1
  _ck $? merge-kept-a-rewrite-under-a-release-that-adds-a-line
  ( cd "$gu" && land_changelog_misfiled up ua && ! land_changelog_misfiled u0 ua && ! land_changelog_misfiled up uw &&
    land_changelog_misfiled up ug ) >/dev/null 2>&1
  _ck $? screen-batched-a-PR-whose-clean-changelog-merge-misfiles

  # ---- 5c · PHASE 3b: a rebased delta is walked alone before the full gate; a live one is not. ----
  land_prewalk_needed aaaa; _ck $? prewalk-skipped-for-a-rebased-delta
  land_prewalk_needed ''; [ $? = 1 ]; _ck $? prewalk-ran-for-a-delta-the-landing-did-not-rebase
  printf 'corpus manifest: rows=8\ncorpus manifest: match by the declared delta — x\n' > "$st/pw-ok"
  [ "$(land_prewalk_outcome 0 "$st/pw-ok")" = realised ]; _ck $? prewalk-missed-a-realised-delta
  #      The log's shape is #1215's real pre-walk: the walk's self-test banners (which name
  #      compile_timeout and TIMED-OUT on every run) come first, then the report, then the verdict.
  { echo 'corpus manifest: stream separation self-test ok (child hash stable, supervisor stderr separate, run rc=124, compile_timeout preserved)'
    echo '  unrealised, mispredicted (exit, hash, class), wrong result, malformed and TIMED-OUT deltas refused;'
    echo 'corpus delta: the fresh manifest does NOT differ from the committed one by exactly the declared delta'
    printf '  MISPREDICTED  x86_64   test/n.al  declared ADDED  - -> run/7 out:e3b0c442 err:e3b0c442\n'
    printf '%72s observed ADDED  - -> run/132 out:e3b0c442 err:e3b0c442\n' ''
    echo 'corpus delta: 0 undeclared, 0 unrealised, 1 mispredicted pair(s)'
    echo 'corpus manifest: MISMATCH against the declared delta in scripts/corpus.expected-delta (report above)'; } > "$st/pw-red"
  [ "$(land_prewalk_outcome 1 "$st/pw-red")" = unrealised ]; _ck $? prewalk-missed-an-unrealised-delta
  [ "$(land_prewalk_outcome 0 "$st/pw-red")" = unknown ]; _ck $? prewalk-refused-on-a-log-its-exit-contradicts
  sed 's|- -> run/132 out|- -> run_timeout/124 out|' "$st/pw-red" > "$st/pw-to"
  [ "$(land_prewalk_outcome 1 "$st/pw-to")" = unknown ]; _ck $? prewalk-refused-on-a-timeout
  [ "$(land_prewalk_report "$st/pw-red" | grep -c '')" = 5 ]; _ck $? prewalk-report-is-not-the-delta-report-alone
  printf 'error: seed build failed\n' > "$st/pw-died"
  [ "$(land_prewalk_outcome 1 "$st/pw-died")" = unknown ]; _ck $? prewalk-refused-on-a-walk-that-never-ran
  printf 'corpus manifest: match (8 rows)\n' > "$st/pw-inert"
  [ "$(land_prewalk_outcome 0 "$st/pw-inert")" = unknown ]; _ck $? prewalk-took-a-plain-match-as-the-rebased-delta

  # ---- 6 · the oracle commit PHASE 6a makes is exactly one path. ----------------------------
  oracle_commit_paths_check scripts/corpus.manifest >/dev/null 2>&1
  _ck $? oracle-paths-refused-a-manifest-only-commit
  oracle_commit_paths_check "$(printf '%s\n%s' scripts/corpus.manifest src/lower.al)" >/dev/null 2>&1
  [ $? = 1 ]; _ck $? oracle-paths-allowed-a-source-file-beside-the-manifest
  oracle_commit_paths_check "$(printf '%s\n%s' scripts/corpus.manifest scripts/xbackend_diff.baseline)" >/dev/null 2>&1
  [ $? = 1 ]; _ck $? oracle-paths-allowed-the-ratchet-line-beside-the-manifest
  oracle_commit_paths_check '' >/dev/null 2>&1
  [ $? = 1 ]; _ck $? oracle-paths-allowed-an-empty-commit

  # ---- 6a · an attribution trailer is refused, and prose that mentions it is not. ----------
  out="$(attribution_trailer_check 'commit deadbeef' "$(printf '%s\n%s' 'fix(x): y' 'Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>')" 2>&1)"
  [ $? = 1 ]; _ck $? attribution-allowed-a-commit-carrying-the-trailer
  case "$out" in *'second author of record'*'noreply@anthropic.com'*) _ck 0 x ;;
                 *) _ck 1 attribution-did-not-name-the-trailer-line ;; esac
  # Every spelling the tooling has actually emitted, and every case of it.
  local spell
  for spell in 'Co-authored-by: X <x@y>' 'CO-AUTHORED-BY: X <x@y>' 'Assisted-by: Copilot' 'AI-assisted: yes' 'Generated with: some-tool'; do
    attribution_trailer_check 'commit v' "$(printf '%s\n%s' 'fix(x): y' "$spell")" >/dev/null 2>&1
    [ $? = 1 ]; _ck $? "attribution-allowed-the-$spell-spelling"
  done
  # The eraser control: an ordinary body must pass. A predicate that refused every message would
  # satisfy every case above and block every landing.
  attribution_trailer_check 'PR #1 body' "$(printf '%s\n%s' '## Summary' 'Fixes the thing. Verified by the full gate.')" >/dev/null 2>&1
  _ck $? attribution-refused-an-ordinary-PR-body
  # Prose that MENTIONS the rule is not a trailer: the commit adding this rule, and AGENTS.md,
  # both write the word. Only trailer syntax at line start is refused.
  attribution_trailer_check 'commit rule' "$(printf '%s\n%s' 'docs(agents): forbid the co-author attribution trailer' 'The rule: no agent adds a co-author trailer to a commit message, because')" >/dev/null 2>&1
  _ck $? attribution-refused-prose-mentioning-a-co-author-trailer
  # Indentation does not excuse it, and a trailer below the body is still a trailer.
  attribution_trailer_check 'commit indented' "$(printf '%s\n%s' 'fix(x): y' '   Co-Authored-By: X <x@y>')" >/dev/null 2>&1
  [ $? = 1 ]; _ck $? attribution-allowed-an-indented-trailer

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
  main_provenance_step 1 - "$(printf '%s\n' package.al seed/alatyr seed/VERSION seed/HISTORY.md scripts/package_cli_test.sh CHANGELOG.md)" r1 >/dev/null 2>&1
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
  if [ "$k" -ne "$LAND_SELFTEST_EXPECTED" ]; then
    echo "*** land self-test: ran $k checks, expected exactly $LAND_SELFTEST_EXPECTED — a self-test" >&2
    echo "    that reports fewer checks than it owes is a failure, not a shortcut to green, and more" >&2
    echo "    means the count was not updated (or a merge kept a stale one) ***" >&2
    return 1
  fi
  echo "ok   land PR-shape self-test: $k checks — the oracle-mixing, seed-binary, seed/VERSION"
  echo "     append-only, one-file-oracle-commit, predicted-delta base, oracle-commit path-set and"
  echo "     main-provenance refusals and the push-capability probe, each in both directions, and the"
  echo "     predicted-delta decider"
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
  if [ "$(cat "$LAND_ST/checks")" -ne "$LAND_SELFTEST_EXPECTED" ]; then
    echo "land self-test: recorded $(cat "$LAND_ST/checks") checks, expected exactly $LAND_SELFTEST_EXPECTED" >&2
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
DO_SCREEN=0
for a in "${@:2}"; do
  case "$a" in
    --push) DO_PUSH=1 ;;
    --screen) DO_SCREEN=1 ;;
    --no-rewalk) DO_REWALK=0 ;;
    *) die "unknown option: $a" ;;
  esac
done

# --- PHASE 0 — preconditions ----------------------------------------------------------------------
# Each of these has cost somebody a measurement. A dirty tree makes "the gate ran on the merge" false;
# a stash means uncommitted work exists that the gate cannot see; a missing `gh` means the PR head
# cannot be fetched at all.
say "PHASE 0 — preconditions"
command -v gh  >/dev/null 2>&1 || die "gh is required to resolve PR #$PR"
command -v git >/dev/null 2>&1 || die "git is required"
DIRT="$(land_tree_dirty "$(git status --porcelain)")" && die "the integration checkout is dirty; commit or clean it first:
$DIRT"
[ -z "$(git stash list)" ] || die "a stash exists. \`git stash\` is forbidden here (one ref per repository,
     and two trees stashing at once swap each other's work). Resolve it before landing."
git rev-parse --verify -q refs/heads/main >/dev/null || die "no local main"
echo "  clean tree, no stash, gh present"

## PUSH CAPABILITY (#1085). `--push` reaches PHASE 7 and runs the one irreversible command in this
## procedure. On `omen` it sat there for ~30 minutes with ZERO bytes of I/O — no credential helper
## configured (`git config --get credential.helper` empty), `gh` not on PATH even inside `nix develop`,
## although `~/.config/gh/hosts.yml` held a valid token. A stall at the publish step is worse than a
## refusal: the gate has already cost ~90 minutes by then, and nothing tells you why nothing is happening.
## An SSH remote needs no helper; an HTTPS one needs a helper OR a token in the environment.
if [ "$DO_PUSH" = 1 ]; then
  REMOTE_URL="$(git remote get-url origin 2>/dev/null || true)"
  CRED_HELPER="$(land_cred_helper_for "$REMOTE_URL")"
  if ! land_push_capability_ok "$REMOTE_URL" "$CRED_HELPER" "${GH_TOKEN:-}${GITHUB_TOKEN:-}"; then
    die "this checkout cannot push over HTTPS: remote is '$REMOTE_URL', no credential.helper is configured
     for that URL (generic or host-specific key) and neither \$GH_TOKEN nor \$GITHUB_TOKEN is set.
     Gate the tree here if you want, but publish from a checkout that can (the same object, the
     same --force-with-lease). Run \`gh auth setup-git\` there."
  fi
  echo "  push capability: present"
fi

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
land_fetch_pr_ref origin "$PR" "$PR_REF" \
  || die "fetch failed: could not update $PR_REF from origin refs/pull/$PR/head (or origin main)"
git rev-parse --verify -q "$PR_REF" >/dev/null || die "no selected PR head on origin"
BASE="$(git rev-parse origin/main)"
HEAD_SHA="$(git rev-parse "$PR_REF")"
[ "$HEAD_SHA" = "$HEAD_OID" ] || die "selected PR head changed while fetching"
## The merge queue (#1127) names the head its reviewer approved; any other object is not this landing's.
if [ -n "${ALATYR_LAND_EXPECT_HEAD:-}" ] && [ "$HEAD_SHA" != "$ALATYR_LAND_EXPECT_HEAD" ]; then
  verdict "LAND REFUSED (head moved) — the PR head is $HEAD_SHA, the reviewed head is $ALATYR_LAND_EXPECT_HEAD"
  exit 1
fi
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
attribution_trailer_check "PR #$PR body" "$PR_BODY" || shape_fail=1
for c in $(git rev-list "$BASE..$HEAD_SHA"); do
  COMMIT_OBJECT="$(git cat-file commit "$c")" || die "could not read commit $c"
  COMMIT_MESSAGE="${COMMIT_OBJECT#*$'\n\n'}"
  COMMIT_BODY="${COMMIT_MESSAGE#*$'\n\n'}"
  message_shape_check "commit $c" "$COMMIT_BODY" || shape_fail=1
  attribution_trailer_check "commit $c" "$COMMIT_MESSAGE" || shape_fail=1
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
## LANDING_DELTA is the prediction this landing gates and PHASE 3 puts into the merge: the PR's own
## file when it is live, its rebase onto BASE's manifest when it was stale (#1264). The PR's branch is
## never rewritten; the merge commit carries the rebased copy and says so.
LANDING_DELTA=
DELTA_REBASED_FROM=
LD_DIR="$ROOT/target/land-delta-$PR"
pr_delta_base_check "$CHANGED" "$DELTA_DECLARED_BASE" "$BASE_MANIFEST_SHA"; dbc_rc=$?
case "$dbc_rc" in
  0)
    if printf '%s\n' "$CHANGED" | grep -qx "$DELTA_REL" && [ "$DELTA_DECLARED_BASE" != absent ]; then
      rm -rf "$LD_DIR"; mkdir -p "$LD_DIR" && git show "$HEAD_SHA:$DELTA_REL" > "$LD_DIR/pr.delta" ||
        die "could not stage $DELTA_REL under $LD_DIR"
      LANDING_DELTA="$LD_DIR/pr.delta"
    fi ;;
  3)
    rm -rf "$LD_DIR"; mkdir -p "$LD_DIR" && git show "$HEAD_SHA:$DELTA_REL" > "$LD_DIR/pr.delta" &&
      git show "$BASE:scripts/corpus.manifest" > "$LD_DIR/base.manifest" ||
      die "could not stage $DELTA_REL and main's manifest under $LD_DIR"
    if ! land_manifest_by_sha "$DELTA_DECLARED_BASE" "$LD_DIR/old.manifest" \
           "$(git merge-base "$BASE" "$HEAD_SHA")" "$HEAD_SHA" $(git rev-list -n 60 "$BASE" -- scripts/corpus.manifest); then
      echo "  REFUSE: no manifest with sha256 $DELTA_DECLARED_BASE is in reach (the PR's merge base, its"
      echo "          head, or the last 60 versions on main), so the rebase cannot check that the delta's rows"
      echo "          rebuild its own result. Rebase onto main and re-emit it with --emit-expected."
      shape_fail=1
    elif bash scripts/corpus_manifest.sh --rebase-delta "$LD_DIR/pr.delta" "$LD_DIR/base.manifest" \
           "$LD_DIR/rebased.delta" --rebase-from "$LD_DIR/old.manifest" > "$LD_DIR/rebase.log" 2>&1; then
      sed 's/^/  /' "$LD_DIR/rebase.log"
      LANDING_DELTA="$LD_DIR/rebased.delta"
      DELTA_REBASED_FROM="$DELTA_DECLARED_BASE"
    else
      sed 's/^/  /' "$LD_DIR/rebase.log"
      echo "  REFUSE: $DELTA_REL is stale and cannot be rebased mechanically (above). Rebase onto main and"
      echo "          re-emit it with scripts/corpus_manifest.sh --emit-expected from a walk of the rebased branch."
      shape_fail=1
    fi ;;
  *) shape_fail=1 ;;
esac
[ -n "$LANDING_DELTA" ] &&
  echo "  predicted delta: $DELTA_REL declares $(sed -n 's/^pairs=//p' "$LANDING_DELTA") pair(s) against main's manifest$([ -n "$DELTA_REBASED_FROM" ] && echo ' (rebased)')"
dels=0
for _sf in seed/VERSION seed/HISTORY.md; do
  printf '%s\n' "$CHANGED" | grep -qx "$_sf" || continue
  _n="$(git diff "$BASE...$HEAD_SHA" -- "$_sf" | grep -E '^-' | grep -v '^--- ' |
        pr_seed_version_protected_deletions "$_sf")"
  dels=$((dels + ${_n:-0}))
done
pr_xbackend_baseline_edit_check "$CHANGED" || shape_fail=1
if git cat-file -e "$HEAD_SHA:scripts/known-deviations.issues.tsv" 2>/dev/null; then
  DEV_OPEN="$(gh issue list -R "$REPO" --state open --limit 5000 --json number --jq '.[].number' 2>/dev/null)" || DEV_OPEN=""
  pr_deviation_issues_open_check "$(git show "$HEAD_SHA:scripts/known-deviations.issues.tsv")" "$DEV_OPEN" || shape_fail=1
fi
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
if [ "$DO_SCREEN" = 1 ]; then
  SOLO=no
  printf '%s\n' "$CHANGED" | grep -qx -e scripts/corpus.manifest -e scripts/idiom.baseline \
    -e scripts/needle.baseline -e "$DELTA_REL" && SOLO=yes
  ## The queue composes a batch with plain merges and never resolves one, so a PR that conflicts with
  ## main only in CHANGELOG.md lands alone, through PHASE 3, which settles it (#1312).
  if [ "$SOLO" = no ] && land_changelog_only_conflict "$BASE" "$HEAD_SHA"; then
    SOLO=yes; echo "  CHANGELOG.md conflicts with main and nothing else does: solo, so PHASE 3 settles it"
  fi
  if [ "$SOLO" = no ] && land_changelog_misfiled "$BASE" "$HEAD_SHA"; then
    SOLO=yes; echo "  a clean merge files a CHANGELOG.md line under a release heading: solo, so PHASE 3 moves it (#1319)"
  fi
  [ "$IS_FORK" = no ] || { verdict "LAND REFUSED (screen) — a fork PR is landed by hand, never by the queue"; exit 1; }
  echo "land-screen: pr=$PR head=$HEAD_SHA solo=$SOLO link=$ISSUE_LINK"
  verdict "SCREEN OK — nothing was merged"
  exit 0
fi
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
DELTA_NOTE="$DELTA_REL: the PR's own prediction, taken over the copy on main."
[ -n "$DELTA_REBASED_FROM" ] && DELTA_NOTE="$DELTA_REL: the PR's prediction rebased from manifest
$(printf '%s' "$DELTA_REBASED_FROM" | cut -c1-12) onto $(printf '%s' "$BASE_MANIFEST_SHA" | cut -c1-12) by scripts/corpus_manifest.sh --rebase-delta (#1264).
Its rows are the PR's verbatim; base_sha256 and result_sha256 are recomputed."
land_merge_pr "$PR_REF" "merge #$PR: ${HEAD_LABEL:-pr-$PR}" "$ISSUE_LINK" "$LANDING_DELTA" "$DELTA_NOTE" || {
  git merge --abort 2>/dev/null
  git switch --quiet - 2>/dev/null
  verdict "LAND REFUSED (the merge conflicts) — ask for a rebase onto $BASE"
  exit 1
}
M="$(git rev-parse HEAD)"
echo "  merged as $M"
[ -n "$LANDING_DELTA" ] && ! git diff --quiet "$PR_REF" "$M" -- "$DELTA_REL" &&
  echo "  $DELTA_REL in the merge is $LANDING_DELTA; the PR's branch is unchanged"
echo "  a reseed, if one is owed, is committed ON TOP OF THIS COMMIT, before the gate runs —"
echo "  so that the fixpoint that is verified is the fixpoint that ships."

# --- PHASE 3b — the corpus pre-walk, when PHASE 2 rebased the delta (#1264) -----------------------
# See land_prewalk_needed: the rebased rows are a hypothesis about main's code, and this tests it in
# minutes. It builds the merged compiler the way fixpoint.sh does (seed -> Stage1 -> Stage2) and runs
# the corpus stage alone. Only an `unrealised` answer stops here; full.sh rebuilds and re-walks anyway.
if land_prewalk_needed "$DELTA_REBASED_FROM"; then
  say "PHASE 3b — corpus pre-walk: does the merged tree realise the REBASED $DELTA_REL? (~15 min: two self-builds and one walk)"
  PW_LOG="$ROOT/target/land-prewalk.log"
  ( ulimit -c 0; nix develop -c bash -c '
      rm -f target/debug/alatyr target/debug/alatyr.s target/debug/alatyr.o &&
      seed/alatyr build package.al && cp target/debug/alatyr target/land-prewalk-stage1 &&
      target/land-prewalk-stage1 build package.al && rm -f target/land-prewalk-stage1 &&
      bash scripts/corpus_manifest.sh --check' ) > "$PW_LOG" 2>&1
  pw_rc=$?
  grep -E '^corpus manifest: (rows=|match|MISMATCH)' "$PW_LOG" | sed 's/^/  /'
  case "$(land_prewalk_outcome "$pw_rc" "$PW_LOG")" in
    realised) echo "  the walk realises the rebased delta; the full gate decides" ;;
    unrealised)
      echo "  The rebased delta is NOT what the merged tree does: the rows were measured on the PR's old base,"
      echo "  and main's code changed what they describe (or they never held). The walk's report"
      echo "  (log $PW_LOG):"
      land_prewalk_report "$PW_LOG" | head -n 60 | sed 's/^/  pre-walk MISMATCH | /'
      echo "  Rebase the branch onto main and re-emit $DELTA_REL from a native walk of it (--emit-expected)."
      verdict "NOT LANDABLE — the corpus pre-walk does not realise the rebased $DELTA_REL; the full gate was not run"
      echo "The merge commit $M is left in place, detached, for inspection. \`git switch main\` to leave it."
      exit 1 ;;
    *) echo "  the pre-walk gave no answer on the prediction (rc $pw_rc, log $PW_LOG); the full gate decides" ;;
  esac
fi

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
    printf '%s (base %s, result %s)' "$DELTA_REL" "$(printf '%s' "$BASE_MANIFEST_SHA" | cut -c1-12)" "$(printf '%s' "$O_RESULT" | cut -c1-12)"
    [ -n "$DELTA_REBASED_FROM" ] && printf ',\nrebased by PHASE 2 from the PR'"'"'s prediction against %s (#1264)' "$(printf '%s' "$DELTA_REBASED_FROM" | cut -c1-12)"
    printf ', so this commit\n'
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
  attribution_trailer_check "oracle commit $O" "$(git log -1 --format=%B "$O")" || o_fail=1
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

  # --- PHASE 6c — the xbackend baseline follows the oracle, never the PR ----------------------
  ## The gate held the line on existing paths and reported what it newly covered. Once this lands
  ## those paths ARE existing, so a baseline that did not move would refuse the NEXT landing on rows
  ## this one legitimately added — a permanently red gate, which is the failure xb_ratchet itself says
  ## it exists to avoid. The landing owns the move; the PR cannot (PHASE 2 refuses it, #1019).
  NEWP="$(printf '%s\n' "$O_RATCHET" | sed -n 's/^xbackend diff: .*new-paths=\([0-9]*\).*$/\1/p' | head -1)"
  NEWR="$(printf '%s\n' "$O_RATCHET" | sed -n 's/^xbackend diff: .*new-rows=\([0-9]*\).*$/\1/p' | head -1)"
  NEWP="${NEWP:-0}"; NEWR="${NEWR:-0}"
  SEENP="$(printf '%s\n' "$O_RATCHET" | sed -n 's/^xbackend diff: paths=\([0-9]*\).*$/\1/p' | head -1)"
  SEENR="$(printf '%s\n' "$O_RATCHET" | sed -n 's/^xbackend diff: paths=[0-9]* rows=\([0-9]*\).*$/\1/p' | head -1)"
  SEENP="${SEENP:-?}"; SEENR="${SEENR:-?}"
  if [ "$NEWP" -gt 0 ] || [ "$NEWR" -gt 0 ]; then
    say "PHASE 6c — the xbackend baseline moves by the coverage this gate added"
    B_MSG="$ROOT/target/land-baseline-commit.msg"
    bash scripts/xbackend_diff.sh --ratchet --write "$FRESH" > "$ROOT/target/land-baseline-write.log" 2>&1
    bw_rc=$?
    grep -E '^xbackend ratchet:' "$ROOT/target/land-baseline-write.log" | sed 's/^/  /'
    [ "$bw_rc" = 0 ] || { verdict "NOT LANDABLE — writing the xbackend baseline failed (rc $bw_rc)"; exit 1; }
    {
      printf 'chore(gates): xbackend baseline follows the oracle #%s\n\n' "$PR"
      printf 'The gate held the ratchet on the %s paths and %s rows that already had a test, and\n' "$SEENP" "$SEENR"
      printf 'reported %s path(s) and %s row(s) as NEWLY COVERED — fixtures this change adds, whose\n' "$NEWP" "$NEWR"
      printf 'cross-backend difference was already in the compiler with no test on it. After this lands\n'
      printf 'those paths are existing, so the line moves by exactly that coverage and by nothing else.\n\n'
      printf 'scripts/xbackend_diff.sh --ratchet --write on the gated manifest, verbatim:\n\n'
      grep -E '^xbackend (diff|ratchet):' "$ROOT/target/land-baseline-write.log" | sed 's/^/  /'
      printf '\nThe PR itself was refused if it touched this file (scripts/land.sh PHASE 2, #1019).\n'
      [ -n "$ISSUE" ] && printf '\nRefs #%s\n' "$ISSUE"
    } > "$B_MSG"
    git add scripts/xbackend_diff.baseline
    git commit --quiet --no-verify -F "$B_MSG" || die "could not create the baseline commit"
    B="$(git rev-parse HEAD)"
    attribution_trailer_check "baseline commit $B" "$(git log -1 --format=%B "$B")" || o_fail=1
    B_PATHS="$(git diff --name-only "$O" "$B")"
    [ "$B_PATHS" = "scripts/xbackend_diff.baseline" ] ||
      { echo "  FAIL: the baseline commit changes more than the baseline: $B_PATHS"; o_fail=1; }
    [ "$o_fail" = 0 ] || { verdict "NOT LANDABLE — the baseline commit failed its shape checks"; exit 1; }
    echo "  baseline commit $B: scripts/xbackend_diff.baseline alone, moved by paths+$NEWP rows+$NEWR"
    PUBLISH="$B"
  fi
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
