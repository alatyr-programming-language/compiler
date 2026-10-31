#!/usr/bin/env bash
# scripts/fixpoint.sh — the TOOL-1 reproducible-build check for the self-hosted Alatyr compiler.
#
#   seed     = seed/alatyr  (a FROZEN, static self-host binary — the bootstrap)
#   Stage1   = target/debug/alatyr (the seed builds the tree under the debug profile)
#   Stage2   = Stage1 builds the tree again
#   FIXPOINT <=>  seed, Stage1, Stage2 all emit BYTE-IDENTICAL GAS for the tree
#
# It also asserts the committed seed is CURRENT (its emission == Stage1's — i.e. seed/ matches src/)
# and that a self-built compiler builds + links + runs an arbitrary program standalone (no seed at
# runtime). Run inside the dev shell (`nix develop`) so `as`/`ld` are on PATH.  Exit 0 = fixpoint.
#
# And it checks, BEFORE building anything, that `seed/VERSION`'s CURRENT SEED block actually describes
# the committed seed. That correspondence used to be maintained entirely by hand, on the one file the
# whole trust chain rests on: a promotion that forgot to update the block left the journal quietly
# describing a different compiler, and the mistake surfaced only when somebody tried to explain a
# reproducibility failure months later. It costs one sha256sum and no build, so it runs first.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
SEED="$ROOT/seed/alatyr"
M="$ROOT/package.al"
[ -x "$SEED" ] || { echo "FAIL: no seed at $SEED"; exit 1; }
step() { printf '=== %s ===\n' "$1"; }

# ---------------------------------------------------------------------------------------------
# THE SEED-IDENTITY DECIDER, and its gate of the gate (issue #600).
#
# Everything below is one function so that a self-test can drive the REAL decision. It was this
# file's uncovered decider: `scripts/fixpoint.sh` had no self-test of any kind, and the
# `package.al` <-> `seed/VERSION` cross-check AGENTS.md leans on was asserted in prose only.
# Measured on the parent, with `package.al` moved to a version the committed seed does not carry:
# turning the version refusal into a note left the stage printing
# `seed identity ok: sha256 8bebf32a… version 9.9.9 (seed/VERSION agrees)` — a false claim in its
# own line — and walking straight on into the build. Nothing anywhere would have said otherwise:
# the version is a compile-time constant that moves the seed's and Stage1's emission IDENTICALLY,
# which is exactly why the fixpoint below cannot catch it and why this check exists at all.
#
# Returns 0 when `seed/VERSION`'s CURRENT SEED block describes the committed seed and agrees with
# `package.al`; 6 otherwise, having said which of the five ways it broke.
# version_older A B — true when A sorts strictly before B as a version (0.2.9 < 0.2.10).
version_older() {
  [ -n "$1" ] && [ -n "$2" ] && [ "$1" != "$2" ] || return 1
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ]
}
seed_identity_check() { # version-file package-file seed-binary
  local VF="$1" M="$2" SEED="$3" f n want_sha want_ver have_sha have_ver MID_PROMOTION=0
  FP_MID_PROMOTION=0  # global: the caller reads it to keep a flagged run from ever passing as the proof
  [ -f "$VF" ] || { echo "FAIL: no seed/VERSION at $VF"; return 6; }
  field() { # <name> -> the single value, or empty when the line is absent
    grep -oE "^${1}:[[:space:]]*[^[:space:]]+" "$VF" 2>/dev/null | head -1 | sed -E "s/^${1}:[[:space:]]*//"
  }
  field_count() { grep -cE "^${1}:" "$VF" 2>/dev/null; true; }
  # Two lines naming the same field is an ambiguity, not a value. A promotion that APPENDS a new
  # current-seed line instead of replacing the old one would otherwise be measured against whichever
  # came first, which is the stale one — and silently, since head -1 always yields something.
  for f in current-seed-sha256 current-seed-version; do
    n="$(field_count "$f")"
    if [ "$n" -gt 1 ]; then
      echo "FAIL: seed/VERSION declares '$f' $n times; the CURRENT SEED block must declare it once."
      echo "      A promotion REPLACES those two lines. Appending a second one leaves the stale value"
      echo "      first, which is the one that would be checked."
      return 6
    fi
  done
  want_sha="$(field current-seed-sha256)"
  want_ver="$(field current-seed-version)"
  if [ -z "$want_sha" ] || [ -z "$want_ver" ]; then
    echo "FAIL: seed/VERSION has no CURRENT SEED block (need both 'current-seed-sha256:' and"
    echo "      'current-seed-version:' lines). That block is the only place the file states which"
    echo "      compiler seed/alatyr IS — the entries themselves read in two directions, so the topmost"
    echo "      one is not the newest. See seed/HISTORY.md's reading note."
    return 6
  fi
  have_sha="$(sha256sum "$SEED" | cut -d' ' -f1)"
  # Compare hex case-insensitively. Case carries no meaning in a digest, and rejecting an upper-case
  # copy of the CORRECT hash would fail with "describes a different seed" — a true verdict about a false
  # thing, which is the class of measurement error AGENTS.md warns about by name.
  if [ "$(printf '%s' "$have_sha" | tr 'A-F' 'a-f')" != "$(printf '%s' "$want_sha" | tr 'A-F' 'a-f')" ]; then
    echo "FAIL: seed/VERSION describes a different seed than the one committed."
    echo "      seed/VERSION current-seed-sha256: $want_sha"
    echo "      sha256sum seed/alatyr:            $have_sha"
    echo "      A promotion updates the CURRENT SEED block in the same commit that replaces the seed."
    echo "      If the seed is right and the block is stale, fix the block — never the other way round:"
    echo "      the block is a claim about the artifact, not a place to record a wish."
    return 6
  fi
  have_ver="$(grep -oE '^[[:space:]]*version[[:space:]]*=[[:space:]]*"[^"]*"' "$M" 2>/dev/null | head -1 | sed -E 's/.*"([^"]*)".*/\1/')"
  if [ -z "$have_ver" ]; then
    echo "FAIL: package.al has no version field to compare against seed/VERSION"; return 6
  fi
  if [ "$have_ver" != "$want_ver" ]; then
    echo "FAIL: package.al's version and the promoted seed's version disagree."
    echo "      package.al version:                $have_ver"
    echo "      seed/VERSION current-seed-version: $want_ver"
    echo "      CHANGELOG.md's versioning order moves the version ON a seed promotion and only on one, so"
    echo "      these two must always agree. This fires on both ways of breaking it: a promotion that"
    echo "      forgot the bump, and a bump made without a promotion. Note the version IS part of the"
    echo "      emission — it is a compile-time constant (src/cli.al, TOOL-21) — but changing it moves"
    echo "      the seed's and Stage1's output identically, so the fixpoint below would NOT catch this."
    echo "      They agree even mid-promotion: seed/VERSION's order bumps BOTH before the build (#1104)."
    return 6
  fi
  # THE THIRD AXIS — ASK THE ARTIFACT (#586). The two comparisons above are claims checked against
  # claims: the block's version against package.al's. Both can agree while the binary they describe
  # answers a THIRD thing, and that is exactly the state #586 recorded — `seed/VERSION` said 0.2.0
  # and `./seed/alatyr --version` answered `alatyr 0.1.0`, each true under its own definition, and
  # nothing anywhere noticing. The seed answers now (TOOL-21 was promoted into it), so the claim is
  # checkable, and a green run must not keep saying it cannot be.
  #
  # On a host that cannot execute the seed — it is a static x86_64 ELF, so an arm64 macOS cannot —
  # this half SKIPS and SAYS SO in the verdict line. A skipped check is not a passed check; that is
  # the rule sweeps.sh already follows for a skipped sweep, and the ok line must not claim an asking
  # that did not happen. rc 126/127 is the shell's "cannot execute"; any other status is a real
  # answer from the seed and is judged.
  local ans rc_ask asked=""
  ans="$("$SEED" --version 2>/dev/null)"; rc_ask=$?
  if [ "$rc_ask" = 126 ] || [ "$rc_ask" = 127 ]; then
    echo "note: the seed was NOT asked — this host cannot execute $SEED (rc $rc_ask)."
    echo "      The version cross-check below is therefore UNVERIFIED here; it runs on x86_64 Linux"
    echo "      (the gate box, or the gate.yml runner)."
  elif [ "$rc_ask" != 0 ]; then
    echo "FAIL: asking the seed its version failed (rc $rc_ask); it must answer and exit 0."
    echo "      output: ${ans:-<empty>}"
    return 6
  else
    # The CLI cites the spec revision it conforms to after a comma — `alatyr 0.2.17, spec 1.1.0`
    # (TOOL-21; scripts/package_cli_test.sh pins that exact line). The seed's VERSION block records
    # the compiler's own version on its own axis, so the comparison is on the part BEFORE the comma.
    # A seed that answers only a spec suffix, or nothing before it, still fails: the version must be
    # there and must match.
    asked="${ans#alatyr }"
    asked="${asked%%,*}"
    asked="$(printf '%s' "$asked" | tr -d '[:space:]')"
    if [ "$asked" != "$want_ver" ] && [ "${ALATYR_RESEED:-0}" = "1" ] && version_older "$asked" "$want_ver"; then
      # ALATYR_RESEED=1 — MID-PROMOTION, the one state where the artifact may lag the block (#1104).
      # seed/VERSION's promote order (and alatyr-integrate's reseed section) is "bump FIRST, then
      # build": package.al AND current-seed-version move to the new number before Stage1 is built,
      # because a compiler bakes the version of the tree it was compiled from (#586). Until Stage2 is
      # copied over seed/alatyr, the committed seed therefore answers the PREVIOUS number while the
      # block already names the new one — and without this opt-in fixpoint.sh refused that tree here,
      # before it built anything, so the order the prose requires could not be run.
      # What the opt-in does NOT relax: the digest still has to match (current-seed-sha256 moves only
      # after the build), package.al and the block still have to agree, and the artifact still has to
      # answer, with a version strictly OLDER than the block's. A seed answering a newer or the same-
      # but-garbled number is still #586 and still rc 6. And a flagged run never reports the fixpoint
      # as reached (see the end of this script): the proof is the unflagged run on the promoted tree.
      echo "NOTE: mid-promotion (ALATYR_RESEED=1): the version is bumped ahead of the committed seed."
      echo "      package.al, seed/VERSION current-seed-version: $want_ver  <- the tree about to be built"
      echo "      ./seed/alatyr --version:                       $ans  <- the seed being replaced"
      MID_PROMOTION=1; FP_MID_PROMOTION=1
    elif [ "$asked" != "$want_ver" ]; then
      echo "FAIL: the seed answers a different version than seed/VERSION records."
      echo "      ./seed/alatyr --version:         $ans"
      echo "      seed/VERSION current-seed-version: $want_ver"
      echo "      The block is a claim ABOUT THE ARTIFACT, so the artifact governs: either the block is"
      echo "      stale, or the promoted binary is not the one the block describes. AGENTS.md's"
      echo "      bump-precedes-the-build order makes the promoted Stage2 answer the version it is"
      echo "      released under; a disagreement here means that order was not followed, which is #586."
      if version_older "$asked" "$want_ver"; then
        echo "      If this is a promotion in progress — bumped first, Stage2 not yet copied over the seed —"
        echo "      build the stages with ALATYR_RESEED=1 (#1104); the proof is the unflagged run afterwards."
      fi
      return 6
    fi
  fi
  # The verdict names the version that was VERIFIED, never one merely declared. Mid-promotion that
  # is the seed's own answer, the previous release: printing package.al's number there produced
  # `version 0.2.18 (seed/VERSION agrees; the seed … answered 0.2.17)` on the #1072 reseed run — a
  # verdict line asserting agreement on a number the artifact does not carry, which is the exact
  # defect this file's own header warns about. (Mid-promotion is only ever entered by asking.)
  if [ "${MID_PROMOTION:-0}" = "1" ]; then
    echo "seed identity ok: sha256 ${have_sha:0:16}… version $asked (mid-promotion: the seed was asked and answered $asked; package.al and seed/VERSION are bumped AHEAD to $want_ver, the version of the tree about to be built)"
  elif [ -n "$asked" ]; then
    echo "seed identity ok: sha256 ${have_sha:0:16}… version $want_ver (seed/VERSION agrees; the seed was asked and answered $asked)"
  else
    echo "seed identity ok: sha256 ${have_sha:0:16}… version $want_ver (seed/VERSION agrees; the seed was NOT asked on this host)"
  fi
  return 0
}

## The gate of the gate. Costs one `sha256sum` of a 12-byte file and no build, so it runs on every
## invocation, BEFORE the decision it is about — and in a SUBSHELL, because a `set -u` unbound
## variable or an arithmetic error inside a driven function unwinds to top level and ENDS THE
## SCRIPT, printing nothing at all; the completion marker below is what notices instead.
FIXPOINT_SELFTEST_EXPECTED=50  # +12 for the #1104 opt-in: 4 bump-first tree, 2 verdict line, 1 version order, 5 limits; +5 the end-of-run verdict, +3 the flag reaching it (PR #1105 reviews)
# The verdict at the end of a run, a function so the self-test drives the REAL decision (review of
# PR #1105): a mid-promotion run (ALATYR_RESEED=1) must end at rc 4 and never print the fixpoint
# line, even when seed == Stage1 == Stage2.
fixpoint_verdict() { # mid-promotion(0|1) gas-seed gas1 gas2
  if [ "$1" = 1 ]; then
    echo "mid-promotion: seed=$(wc -l<"$2") gas1=$(wc -l<"$3") gas2=$(wc -l<"$4") lines"
    if [ -s "$3" ] && diff -q "$3" "$4" >/dev/null 2>&1; then
      echo "  Stage1 == Stage2 in the emitted GAS. Build Stage3, promote Stage2, then re-run this script"
      echo "  WITHOUT ALATYR_RESEED: that run, on the promoted tree, is the proof. Not a fixpoint verdict."
    else
      echo "  FAIL: Stage1 != Stage2 in the emitted GAS — nothing here can be promoted."
    fi
    return 4
  fi
  if [ -s "$3" ] && diff -q "$3" "$4" >/dev/null 2>&1 && diff -q "$2" "$3" >/dev/null 2>&1; then
    echo "*** TOOL-1 FIXPOINT: seed == Stage1 == Stage2 ($(wc -l < "$3") lines); self-built compiler builds standalone ***"
    return 0
  fi
  echo "DIFFER: seed=$(wc -l<"$2") gas1=$(wc -l<"$3") gas2=$(wc -l<"$4")"
  echo "  (seed != Stage1 means the committed seed/alatyr is STALE vs src/. The recovery is a SELF-PROMOTE,"
  echo "   not a rebuild from the frozen Rust ancestor — that ancestor can no longer parse the current src/."
  echo "   Build Stage1, let it build Stage2 and Stage3. Require Stage1 == Stage2 == Stage3 in the emitted GAS,"
  echo "   normalizing .L<N> and .Lra<N>_<k> first. In the BINARY require only Stage2 == Stage3: Stage1 was"
  echo "   assembled by the stale seed, so its binary differs by construction. Read that normalized"
  echo "   seed->Stage1 delta line by line, copy STAGE2 — not Stage1 — over seed/alatyr, append the evidence"
  echo "   to seed/HISTORY.md, and re-run this script on the promoted tree. Why Stage2, and what a readable"
  echo "   delta looks like: docs/rationale/reproducibility.md and alatyr-integrate SKILL.md section 3.)"
  return 4
}

fixpoint_seed_identity_selftest() { # work-dir
  local st="$1" bad="" k=0 out rc
  # The self-test drives the REAL decision, so it owns the variable some of its checks are about:
  # a run launched WITH ALATYR_RESEED=1 must not leak the flag into the negative controls, or
  # 'a bump made without a promotion' answers rc=0 and the self-test that is supposed to catch
  # exactly that goes silent — measured, it failed rc=1 with two such labels when the whole
  # fixpoint run carried the flag. Checks that exercise the opt-in set it explicitly per call.
  local ALATYR_RESEED=0
  rm -rf "$st"; mkdir -p "$st" || return 1
  _ck() { k=$((k+1)); [ "$1" = 0 ] || bad="$bad $2"; }
  printf 'a frozen seed\n' > "$st/seed"
  local sha; sha="$(sha256sum "$st/seed" | cut -d' ' -f1)"
  _vf() { # sha-line-value version-line-value [extra lines…]
    { printf 'current-seed-sha256: %s\n' "$1"; printf 'current-seed-version: %s\n' "$2"
      shift 2; for l in "$@"; do printf '%s\n' "$l"; done; } > "$st/VERSION"
  }
  _pkg() { printf 'app := Package(\n  version = "%s",\n)\n' "$1" > "$st/package.al"; }

  # 1 · the agreeing tree is accepted, and says what it agreed on.
  _vf "$sha" 0.4.2; _pkg 0.4.2
  out="$(seed_identity_check "$st/VERSION" "$st/package.al" "$st/seed" 2>&1)"; rc=$?
  [ "$rc" = 0 ]; _ck $? "identity-refused-an-agreeing-tree(rc=$rc: $out)"
  case "$out" in *'version 0.4.2'*) _ck 0 x ;; *) _ck 1 "identity-ok-line-does-not-name-the-version($out)" ;; esac
  case "$out" in "${sha:0:16}"*|*"${sha:0:16}"*) _ck 0 x ;; *) _ck 1 identity-ok-line-does-not-name-the-digest ;; esac

  # 2 · THE VERSION CROSS-CHECK, IN BOTH DIRECTIONS. AGENTS.md states it fires on a promotion that
  #     forgot the bump AND on a bump made without a promotion, and only driving both proves the
  #     comparison is a comparison rather than a one-sided floor.
  _vf "$sha" 0.4.2; _pkg 0.4.3          # package.al ahead — a bump without a promotion
  out="$(seed_identity_check "$st/VERSION" "$st/package.al" "$st/seed" 2>&1)"; rc=$?
  [ "$rc" = 6 ]; _ck $? "identity-accepted-a-package-ahead-of-the-seed(rc=$rc)"
  case "$out" in *"package.al's version and the promoted seed's version disagree"*) _ck 0 x ;;
                 *) _ck 1 "identity-did-not-name-the-version-disagreement($out)" ;; esac
  case "$out" in *0.4.3*0.4.2*) _ck 0 x ;; *) _ck 1 identity-did-not-print-both-versions ;; esac
  _vf "$sha" 0.4.3; _pkg 0.4.2          # seed/VERSION ahead — a promotion that forgot the bump
  seed_identity_check "$st/VERSION" "$st/package.al" "$st/seed" >/dev/null 2>&1
  [ $? = 6 ]; _ck $? identity-accepted-a-seed-VERSION-ahead-of-package.al

  # 3 · the digest half, and the deliberate case-insensitivity beside it. Rejecting an UPPER-CASE
  #     copy of the CORRECT hash would be a true verdict about a false thing.
  _vf "${sha//[0-9a-f]/0}" 0.4.2; _pkg 0.4.2
  out="$(seed_identity_check "$st/VERSION" "$st/package.al" "$st/seed" 2>&1)"; rc=$?
  [ "$rc" = 6 ]; _ck $? "identity-accepted-a-block-describing-another-seed(rc=$rc)"
  case "$out" in *'describes a different seed'*) _ck 0 x ;; *) _ck 1 identity-did-not-name-the-digest-disagreement ;; esac
  _vf "$(printf '%s' "$sha" | tr 'a-f' 'A-F')" 0.4.2; _pkg 0.4.2
  seed_identity_check "$st/VERSION" "$st/package.al" "$st/seed" >/dev/null 2>&1
  [ $? = 0 ]; _ck $? identity-rejected-an-upper-case-copy-of-the-correct-digest

  # 4 · the ambiguity guards: a second line for either field, and a missing block.
  _vf "$sha" 0.4.2 "current-seed-sha256: $sha"; _pkg 0.4.2
  seed_identity_check "$st/VERSION" "$st/package.al" "$st/seed" >/dev/null 2>&1
  [ $? = 6 ]; _ck $? identity-accepted-two-current-seed-sha256-lines
  _vf "$sha" 0.4.2 'current-seed-version: 0.4.2'; _pkg 0.4.2
  seed_identity_check "$st/VERSION" "$st/package.al" "$st/seed" >/dev/null 2>&1
  [ $? = 6 ]; _ck $? identity-accepted-two-current-seed-version-lines
  printf 'no block here\n' > "$st/VERSION"; _pkg 0.4.2
  out="$(seed_identity_check "$st/VERSION" "$st/package.al" "$st/seed" 2>&1)"; rc=$?
  [ "$rc" = 6 ]; _ck $? identity-accepted-a-VERSION-with-no-CURRENT-SEED-block
  case "$out" in *'no CURRENT SEED block'*) _ck 0 x ;; *) _ck 1 identity-did-not-name-the-missing-block ;; esac
  seed_identity_check "$st/nosuchfile" "$st/package.al" "$st/seed" >/dev/null 2>&1
  [ $? = 6 ]; _ck $? identity-accepted-a-missing-VERSION-file

  # 5 · a manifest with no version at all is a refusal, not an empty-string match against an
  #     empty block field: the two are different facts and only one of them is recoverable.
  _vf "$sha" 0.4.2; printf 'app := Package(\n)\n' > "$st/package.al"
  out="$(seed_identity_check "$st/VERSION" "$st/package.al" "$st/seed" 2>&1)"; rc=$?
  [ "$rc" = 6 ]; _ck $? identity-accepted-a-package.al-with-no-version
  case "$out" in *'no version field'*) _ck 0 x ;; *) _ck 1 identity-did-not-name-the-missing-version-field ;; esac

  # 6 · THE THIRD AXIS (#586): the seed is ASKED. A block and a manifest can agree with each other
  #     while the binary they describe answers a third thing — the exact state #586 recorded
  #     (block 0.2.0, `seed/alatyr --version` → 0.1.0). A fake seed answers, so the comparison is
  #     driven rather than assumed, and the skip path is driven too: a host that cannot execute the
  #     seed must say it skipped, not claim an asking that never happened.
  _ans() { # version -> an executable answering `alatyr <version>`; re-record the digest it carries
    printf '#!/bin/sh\nprintf "alatyr %s\\n" "%s"\n' "$1" "$1" > "$st/seed"; chmod +x "$st/seed"
    sha="$(sha256sum "$st/seed" | cut -d' ' -f1)"; _vf "$sha" 0.4.2
  }
  _pkg 0.4.2; _ans 0.4.2
  out="$(seed_identity_check "$st/VERSION" "$st/package.al" "$st/seed" 2>&1)"; rc=$?
  [ "$rc" = 0 ]; _ck $? "identity-refused-a-seed-answering-the-recorded-version(rc=$rc)"
  case "$out" in *'was asked and answered 0.4.2'*) _ck 0 x ;;
                 *) _ck 1 "identity-ok-line-did-not-report-the-asking($out)" ;; esac
  _ans 0.1.0
  out="$(seed_identity_check "$st/VERSION" "$st/package.al" "$st/seed" 2>&1)"; rc=$?
  [ "$rc" = 6 ]; _ck $? "identity-accepted-a-seed-answering-another-version(rc=$rc)"
  case "$out" in *0.1.0*0.4.2*) _ck 0 x ;;
                 *) _ck 1 "identity-did-not-name-both-the-asked-and-the-recorded($out)" ;; esac
  # THE SPEC SUFFIX (the 0.2.17 promotion met this): the CLI answers `alatyr <ver>, spec <pin>`, so a
  # check that compares the whole answer against the recorded version refuses its own compiler. Both
  # directions are driven here — a suffixed answer that carries the recorded version must pass, and one
  # that carries another must still fail, or the parse would be a rubber stamp.
  _ans_suffix() { # answer -> an executable answering exactly that line; re-record the digest it carries
    printf "#!/bin/sh\nprintf '%s\\\\n'\n" "$1" > "$st/seed"; chmod +x "$st/seed"
    sha="$(sha256sum "$st/seed" | cut -d' ' -f1)"; _vf "$sha" 0.4.2
  }
  _ans_suffix 'alatyr 0.4.2, spec 1.1.0'
  out="$(seed_identity_check "$st/VERSION" "$st/package.al" "$st/seed" 2>&1)"; rc=$?
  [ "$rc" = 0 ]; _ck $? "identity-refused-a-seed-answering-the-recorded-version-with-a-spec-suffix(rc=$rc)"
  case "$out" in *'was asked and answered 0.4.2'*) _ck 0 x ;;
                 *) _ck 1 "identity-ok-line-did-not-report-the-suffixed-asking($out)" ;; esac
  _ans_suffix 'alatyr 0.1.0, spec 1.1.0'
  out="$(seed_identity_check "$st/VERSION" "$st/package.al" "$st/seed" 2>&1)"; rc=$?
  [ "$rc" = 6 ]; _ck $? "identity-accepted-a-suffixed-answer-naming-another-version(rc=$rc)"
  case "$out" in *0.1.0*0.4.2*) _ck 0 x ;;
                 *) _ck 1 "identity-did-not-name-both-sides-of-a-suffixed-disagreement($out)" ;; esac
  _ans_suffix 'alatyr , spec 1.1.0'
  out="$(seed_identity_check "$st/VERSION" "$st/package.al" "$st/seed" 2>&1)"; rc=$?
  [ "$rc" = 6 ]; _ck $? "identity-accepted-an-answer-with-no-version-before-the-comma(rc=$rc)"

  printf '#!/bin/sh\nprintf "alatyr 0.4.2\\n"\nexit 3\n' > "$st/seed"; chmod +x "$st/seed"
  sha="$(sha256sum "$st/seed" | cut -d' ' -f1)"; _vf "$sha" 0.4.2
  out="$(seed_identity_check "$st/VERSION" "$st/package.al" "$st/seed" 2>&1)"; rc=$?
  [ "$rc" = 6 ]; _ck $? "identity-accepted-a-seed-that-failed-to-answer(rc=$rc)"
  case "$out" in *'asking the seed its version failed'*) _ck 0 x ;;
                 *) _ck 1 "identity-did-not-name-the-failed-asking($out)" ;; esac
  _ans 0.4.2; chmod -x "$st/seed"
  out="$(seed_identity_check "$st/VERSION" "$st/package.al" "$st/seed" 2>&1)"; rc=$?
  [ "$rc" = 0 ]; _ck $? "identity-failed-on-a-host-that-cannot-execute-the-seed(rc=$rc)"
  case "$out" in *'NOT asked'*) _ck 0 x ;;
                 *) _ck 1 "identity-claimed-an-asking-it-could-not-do($out)" ;; esac

  # 1104 · the mid-promotion opt-in. seed/VERSION's order is "bump FIRST, then build": package.al and
  #        current-seed-version both move to the new number, the digest and the binary do not yet. So
  #        the seed answers the PREVIOUS number while block and manifest agree on the next one, and
  #        fixpoint.sh refused that tree before any stage built. These drive the opt-in and, more
  #        importantly, its LIMITS: the artifact still governs, so an opt-in cannot mask #586.
  _bumped() { # seed-answer block-and-package-version -> a bump-first tree over a seed answering $1
    _ans "$1"; _vf "$sha" "$2"; _pkg "$2"
  }
  _bumped 0.4.2 0.4.3
  out="$(seed_identity_check "$st/VERSION" "$st/package.al" "$st/seed" 2>&1)"; rc=$?
  [ "$rc" = 6 ]; _ck $? "identity-accepted-a-bump-first-tree-without-the-flag(rc=$rc)"
  case "$out" in *'ALATYR_RESEED=1'*) _ck 0 x ;;
                 *) _ck 1 "identity-refusal-did-not-name-the-opt-in($out)" ;; esac
  out="$(ALATYR_RESEED=1 seed_identity_check "$st/VERSION" "$st/package.al" "$st/seed" 2>&1)"; rc=$?
  [ "$rc" = 0 ]; _ck $? "identity-refused-a-bump-first-tree-with-the-flag(rc=$rc: $out)"
  case "$out" in *'mid-promotion'*) _ck 0 x ;;
                 *) _ck 1 "opt-in-did-not-say-it-was-mid-promotion($out)" ;; esac
  # The VERDICT LINE names the version that was verified, the seed's answer, and marks the bump as
  # ahead of it: on the #1072 run it claimed `version 0.2.18 (seed/VERSION agrees …)` for a seed
  # answering 0.2.17.
  case "$out" in *'version 0.4.2 (mid-promotion'*) _ck 0 x ;;
                 *) _ck 1 "verdict-line-named-the-declared-not-the-verified-version($out)" ;; esac
  case "$out" in *'bumped AHEAD to 0.4.3'*) _ck 0 x ;;
                 *) _ck 1 "verdict-line-did-not-mark-the-bump-ahead($out)" ;; esac
  # Version order, not string order: 0.4.9 -> 0.4.10 is a bump.
  _bumped 0.4.9 0.4.10
  ALATYR_RESEED=1 seed_identity_check "$st/VERSION" "$st/package.al" "$st/seed" >/dev/null 2>&1
  [ $? = 0 ]; _ck $? opt-in-compared-versions-as-strings
  # LIMIT 1: the seed answers a NEWER number than the block. No promotion order produces that; it
  #          is #586 the other way round and stays rc 6 with the flag.
  _bumped 0.4.4 0.4.3
  out="$(ALATYR_RESEED=1 seed_identity_check "$st/VERSION" "$st/package.al" "$st/seed" 2>&1)"; rc=$?
  [ "$rc" = 6 ]; _ck $? "opt-in-masked-a-seed-answering-a-newer-version(rc=$rc)"
  case "$out" in *'different version than seed/VERSION records'*) _ck 0 x ;;
                 *) _ck 1 "opt-in-did-not-still-ask-the-artifact($out)" ;; esac
  # LIMIT 2: half a bump — package.al ahead, the block left behind. The documented order moves both,
  #          so the flag does not make this one runnable: it stays the 'bump without a promotion'.
  _ans 0.4.2; _pkg 0.4.3
  out="$(ALATYR_RESEED=1 seed_identity_check "$st/VERSION" "$st/package.al" "$st/seed" 2>&1)"; rc=$?
  [ "$rc" = 6 ]; _ck $? "opt-in-accepted-a-half-bump(rc=$rc)"
  case "$out" in *"package.al's version and the promoted seed's version disagree"*) _ck 0 x ;;
                 *) _ck 1 "half-bump-refusal-did-not-name-the-disagreement($out)" ;; esac
  # LIMIT 3: the digest. current-seed-sha256 moves only after the build, so mid-promotion it still
  #          describes the committed seed; a block describing another binary stays rc 6.
  _bumped 0.4.2 0.4.3; _vf "${sha//[0-9a-f]/0}" 0.4.3
  ALATYR_RESEED=1 seed_identity_check "$st/VERSION" "$st/package.al" "$st/seed" >/dev/null 2>&1
  [ $? = 6 ]; _ck $? opt-in-masked-a-digest-disagreement

  # 1105 review · the end-of-run verdict. A flagged run must stop at rc 4 without the fixpoint line,
  #        even when all three emissions agree; an unflagged agreeing run reports it at rc 0.
  printf 'a\n' > "$st/g0"; printf 'a\n' > "$st/g1"; printf 'a\n' > "$st/g2"; printf 'b\n' > "$st/gx"
  out="$(fixpoint_verdict 1 "$st/g0" "$st/g1" "$st/g2" 2>&1)"; rc=$?
  [ "$rc" = 4 ]; _ck $? "flagged-run-did-not-end-at-rc-4(rc=$rc)"
  case "$out" in *'TOOL-1 FIXPOINT'*) _ck 1 "flagged-run-printed-the-fixpoint-verdict" ;; *) _ck 0 x ;; esac
  out="$(fixpoint_verdict 0 "$st/g0" "$st/g1" "$st/g2" 2>&1)"; rc=$?
  [ "$rc" = 0 ]; _ck $? "unflagged-agreeing-run-not-rc-0(rc=$rc)"
  case "$out" in *'TOOL-1 FIXPOINT'*) _ck 0 x ;; *) _ck 1 "unflagged-agreeing-run-without-the-verdict" ;; esac
  out="$(fixpoint_verdict 0 "$st/gx" "$st/g1" "$st/g2" 2>&1)"; rc=$?
  [ "$rc" = 4 ]; _ck $? "a-stale-seed-reported-a-fixpoint(rc=$rc)"

  # 1105 review (2nd) · the flag reaches the verdict. The rc-4 checks above drive fixpoint_verdict with
  #        a literal 1; these prove the two links that feed it: seed_identity_check sets the global on a
  #        bump-first tree under the flag (and only there), and the run's one call passes that global.
  _bumped 0.4.2 0.4.3; FP_MID_PROMOTION=x
  ALATYR_RESEED=1 seed_identity_check "$st/VERSION" "$st/package.al" "$st/seed" > "$st/o" 2>&1
  [ "$FP_MID_PROMOTION" = 1 ]; _ck $? "flagged-bump-first-tree-did-not-set-FP_MID_PROMOTION($FP_MID_PROMOTION)"
  _ans 0.4.3; FP_MID_PROMOTION=x
  ALATYR_RESEED=1 seed_identity_check "$st/VERSION" "$st/package.al" "$st/seed" > "$st/o" 2>&1
  [ "$FP_MID_PROMOTION" = 0 ]; _ck $? "a-promoted-tree-under-the-flag-set-FP_MID_PROMOTION($FP_MID_PROMOTION)"
  grep -qx 'fixpoint_verdict "${FP_MID_PROMOTION:-0}" target/gas_seed.s target/gas1.s target/gas2.s' "$ROOT/scripts/fixpoint.sh"
  _ck $? "the-run-does-not-pass-FP_MID_PROMOTION-to-fixpoint_verdict"

  printf '%s' "$bad" > "$st/bad"; printf '%s' "$k" > "$st/checks"; : > "$st/complete"
  if [ -n "$bad" ]; then echo "*** fixpoint seed-identity selftest: FAILED —$bad ***"; return 1; fi
  if [ "$k" -lt "$FIXPOINT_SELFTEST_EXPECTED" ]; then
    echo "*** fixpoint seed-identity selftest: ran $k checks, expected at least"
    echo "    $FIXPOINT_SELFTEST_EXPECTED — a self-test that reports fewer checks than it owes is a"
    echo "    failure, not a shortcut to green ***"
    return 1
  fi
  echo "fixpoint seed-identity selftest: $k checks — the version cross-check in BOTH directions, the"
  echo "  digest comparison and its case-insensitivity, the two duplicate-line guards, a missing"
  echo "  block, a missing file, a manifest with no version, and the seed ASKED in all four states:"
  echo "  answers right, answers wrong, fails to answer, and cannot be executed (the skip says so);"
  echo '  and the spec suffix the CLI cites (`alatyr <ver>, spec <pin>`), in both directions and with'
  echo "  no version before the comma, so the parse cannot become a rubber stamp; and the #1104"
  echo "  mid-promotion opt-in with its limits: a newer answer, a half bump and a foreign digest stay refused"
  return 0
}

step "seed identity — seed/VERSION's CURRENT SEED block vs the committed tree"
FP_ST="$ROOT/target/fixpoint-selftest"
mkdir -p "$ROOT/target"
( fixpoint_seed_identity_selftest "$FP_ST" ); FP_SELFTEST_RC=$?
if [ ! -f "$FP_ST/complete" ]; then
  echo "FAIL: the seed-identity self-test did NOT run to completion (rc=$FP_SELFTEST_RC) — it recorded"
  echo "      no verdict, so this run proves nothing about the seed-identity decision below."
  exit 6
fi
if [ -s "$FP_ST/bad" ]; then
  echo "FAIL: the seed-identity self-test recorded failures — $(cat "$FP_ST/bad")"; exit 6
fi
if [ "$(cat "$FP_ST/checks")" -lt "$FIXPOINT_SELFTEST_EXPECTED" ]; then
  echo "FAIL: the seed-identity self-test recorded $(cat "$FP_ST/checks") checks, expected at least $FIXPOINT_SELFTEST_EXPECTED"; exit 6
fi
[ "$FP_SELFTEST_RC" = 0 ] || exit 6
rm -rf "$FP_ST"

seed_identity_check "$ROOT/seed/VERSION" "$M" "$SEED" || exit 6

mkdir -p target
## Do not let a compiler from a previous self-build satisfy the seed-stage assertion after the
## layout transition. The frozen seed must itself create the profile path; remove only that exact
## compiler-under-test artifact, never package fixture or gate scratch trees.
rm -f "$ROOT/target/alatyr" "$ROOT/target/alatyr.s" "$ROOT/target/alatyr.o"
rm -f "$ROOT/target/debug/alatyr" "$ROOT/target/debug/alatyr.s" "$ROOT/target/debug/alatyr.o"

step "Stage1 — the committed seed builds the tree (alatyr build) -> target/debug/alatyr or legacy target/alatyr"
SEED_LOG="$ROOT/target/fixpoint_seedbuild.log"
"$SEED" build "$M" >"$SEED_LOG" 2>&1
seed_rc=$?
tail -1 "$SEED_LOG"
[ "$seed_rc" = 0 ] || { echo "FAIL: seed build (rc=$seed_rc)"; exit 2; }
if [ -x "$ROOT/target/debug/alatyr" ]; then
  STAGE1="$ROOT/target/debug/alatyr"
else
  STAGE1="$ROOT/target/alatyr"
  [ -x "$STAGE1" ] || { echo "FAIL: seed did not create target/debug/alatyr or legacy target/alatyr"; exit 2; }
  echo "bootstrap transition: frozen seed used legacy target/alatyr; fixpoint comparison remains authoritative"
fi
cp "$STAGE1" "$ROOT/target/stage1"

step "gas — the seed and Stage1 emit the tree's GAS"
"$SEED" "$M" > target/gas_seed.s 2>/dev/null
"$ROOT/target/stage1" "$M" > target/gas1.s 2>/dev/null
echo "seed=$(wc -l < target/gas_seed.s) stage1=$(wc -l < target/gas1.s) lines"

step "Stage2 — Stage1 builds the tree -> target/debug/alatyr (then emits GAS)"
"$ROOT/target/stage1" build "$M" >/dev/null 2>&1
STAGE2="$ROOT/target/debug/alatyr"
[ -x "$STAGE2" ] || { echo "FAIL: Stage1 did not build target/debug/alatyr"; exit 3; }
cp "$STAGE2" "$ROOT/target/stage2"
"$ROOT/target/stage2" "$M" > target/gas2.s 2>/dev/null
echo "stage2=$(wc -l < target/gas2.s) lines"

step "self-sufficiency — Stage1 builds+links+runs an arbitrary program (no seed at runtime)"
printf 'main := fn() -> u64 { return 7 + 35 }\n' > target/smoke.al
"$ROOT/target/stage1" -o target/smoke.out "$ROOT/target/smoke.al" 2>/dev/null
"$ROOT/target/smoke.out" 2>/dev/null; sc=$?
[ "$sc" = 42 ] || { echo "FAIL: self-built compiler standalone (smoke exit=$sc, want 42)"; exit 5; }
echo "smoke = $sc (self-built compiler builds standalone)"

step "fixpoint"
# A mid-promotion run (ALATYR_RESEED=1, #1104) builds the stages, and a bump with no src/ change can
# leave seed == Stage1 == Stage2 (the version moves both emissions at once). That is still a tree whose
# committed seed answers the previous release, so a flagged run never reports the fixpoint reached:
# the proof is the unflagged run on the promoted tree.
fixpoint_verdict "${FP_MID_PROMOTION:-0}" target/gas_seed.s target/gas1.s target/gas2.s
exit $?
