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
seed_identity_check() { # version-file package-file seed-binary
  local VF="$1" M="$2" SEED="$3" f n want_sha want_ver have_sha have_ver
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
    echo "      one is not the newest. See the HOW TO READ THIS FILE header."
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
    return 6
  fi
  echo "seed identity ok: sha256 ${have_sha:0:16}… version $have_ver (seed/VERSION agrees)"
  return 0
}

## The gate of the gate. Costs one `sha256sum` of a 12-byte file and no build, so it runs on every
## invocation, BEFORE the decision it is about — and in a SUBSHELL, because a `set -u` unbound
## variable or an arithmetic error inside a driven function unwinds to top level and ENDS THE
## SCRIPT, printing nothing at all; the completion marker below is what notices instead.
FIXPOINT_SELFTEST_EXPECTED=17
fixpoint_seed_identity_selftest() { # work-dir
  local st="$1" bad="" k=0 out rc
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
  echo "  block, a missing file and a manifest with no version"
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
if [ -s target/gas1.s ] && diff -q target/gas1.s target/gas2.s >/dev/null 2>&1 && diff -q target/gas_seed.s target/gas1.s >/dev/null 2>&1; then
  echo "*** TOOL-1 FIXPOINT: seed == Stage1 == Stage2 ($(wc -l < target/gas1.s) lines); self-built compiler builds standalone ***"
  exit 0
fi
echo "DIFFER: seed=$(wc -l<target/gas_seed.s) gas1=$(wc -l<target/gas1.s) gas2=$(wc -l<target/gas2.s)"
echo "  (seed != Stage1 means the committed seed/alatyr is STALE vs src/. The recovery is a SELF-PROMOTE,"
echo "   not a rebuild from the frozen Rust ancestor — that ancestor can no longer parse the current src/."
echo "   Build Stage1, let it build Stage2 and Stage3. Require Stage1 == Stage2 == Stage3 in the emitted GAS,"
echo "   normalizing .L<N> and .Lra<N>_<k> first. In the BINARY require only Stage2 == Stage3: Stage1 was"
echo "   assembled by the stale seed, so its binary differs by construction. Read that normalized"
echo "   seed->Stage1 delta line by line, copy STAGE2 — not Stage1 — over seed/alatyr, append the evidence"
echo "   to seed/VERSION, and re-run this script on the promoted tree. Why Stage2, and what a readable"
echo "   delta looks like: AGENTS.md's Reproducibility section and alatyr-integrate SKILL.md section 3.)"
exit 4
