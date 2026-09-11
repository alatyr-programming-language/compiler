#!/usr/bin/env bash
# scripts/brand_census.sh — the Issue #299 / #544-stage-0 brand-identity CENSUS.
#
# `src/sema.al` carries a measurement instrument that counts, and never refuses, the Types
# §4.2/§4.3/§5.4 brand crossings the compiler currently lets through. It writes one row per finding to
# file descriptor 99, which an ordinary invocation does not have open — so the instrument is silent,
# and the compiler's exit status, diagnostics and emitted GAS are the uninstrumented ones. This script
# is what opens the channel.
#
# Usage (inside `nix develop`):
#   bash scripts/brand_census.sh census  [<compiler>]           # count over src/, lib/ and test/
#   bash scripts/brand_census.sh neutral <base-cc> <probe-cc>    # rc + diagnostic bytes must agree
#   bash scripts/brand_census.sh planted [<compiler>]           # prove the counter can fire, and where
#
# `census` prints a per-class total, a per-file breakdown and, for every row, the source line the
# instrument saw. `neutral` is the companion the #507 caveat requires: an instrumented census can
# report confidently and wrongly, so the claim "this build only counts" is proved separately, by
# comparing every tracked fixture's exit status and normalized diagnostic bytes between the two
# compilers with the input tree held fixed. `planted` is the non-vacuity proof: a census that reports
# zero for a surface has to show that its counter could have fired there at all.
#
# `planted` exists because this census did NOT have one, and the cost is issue #679: the counting hook
# `brand_probe_sink` returned early on a tag-7 (array) declared type, so no array-literal element
# crossing anywhere in the tree could produce a row, and the census's non-vacuity had only ever been
# argued on SCALAR sinks. The blindness survived four slices and two tracked reject fixtures.
# `planted` therefore checks BOTH directions on every surface it names: a known crossing must produce
# a row of the expected class, and a LEGAL program must produce none — while its `sinks=` counter
# proves the elements were visited and judged clean rather than never looked at. That last number is
# the whole difference between a clean zero and a blind one.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT" || exit 1
ulimit -c 0
MODE="${1:-census}"
OUT="$ROOT/target/brand_census"; mkdir -p "$OUT"

# One `alatyr check` with the census channel open. The redirection order matters: `99>` must name a
# real file, never a duplicate of an already-redirected stdout (`>/dev/null 99>&1` sends the rows to
# /dev/null and reads as an empty census).
probe_one() { # $1 compiler  $2 source  $3 rows-file
  "$1" check "$2" 99>"$3" >/dev/null 2>"$3.err"
  echo $?
}

census() {
  local CC="${2:-$ROOT/target/debug/alatyr}"
  [ -x "$CC" ] || { echo "brand_census: no compiler at $CC" >&2; exit 1; }
  : > "$OUT/rows.txt"
  : > "$OUT/summaries.txt"

  echo "=== src/ (the compiler's own package: src/*.al plus every ambiently injected lib module) ==="
  local rc; rc=$(probe_one "$CC" package.al "$OUT/src.rows")
  echo "package.al check rc=$rc"
  sed 's/^/  /' "$OUT/src.rows"
  grep -v ' SUMMARY ' "$OUT/src.rows" | sed "s#^#src package.al #" >> "$OUT/rows.txt"
  grep ' SUMMARY ' "$OUT/src.rows" | sed 's#^#src package.al #' >> "$OUT/summaries.txt"

  echo "=== lib/ (per module; a module that does not check standalone is reported, not counted) ==="
  local n_ok=0 n_bad=0
  while read -r f; do
    rc=$(probe_one "$CC" "$f" "$OUT/one.rows")
    if [ "$rc" = 0 ]; then n_ok=$((n_ok+1)); else n_bad=$((n_bad+1)); echo "  NOT-STANDALONE rc=$rc $f"; fi
    grep -v ' SUMMARY ' "$OUT/one.rows" | sed "s#^#lib $f #" >> "$OUT/rows.txt"
    grep ' SUMMARY ' "$OUT/one.rows" | sed "s#^#lib $f rc=$rc #" >> "$OUT/summaries.txt"
  done < <(git ls-files 'lib/**/*.al' 'lib/*.al')
  echo "  lib modules: standalone-checkable=$n_ok not-standalone=$n_bad"

  echo "=== test/ (every tracked fixture) ==="
  local n=0
  while read -r f; do
    n=$((n+1))
    rc=$(probe_one "$CC" "$f" "$OUT/one.rows")
    grep -v ' SUMMARY ' "$OUT/one.rows" | sed "s#^#test $f rc=$rc #" >> "$OUT/rows.txt"
    grep ' SUMMARY ' "$OUT/one.rows" | sed "s#^#test $f rc=$rc #" >> "$OUT/summaries.txt"
  done < <(git ls-files 'test/*.al')
  echo "  fixtures checked: $n"

  echo "=== census by class ==="
  awk '{for(i=1;i<=NF;i++) if($i=="#299"){print $(i+1); break}}' "$OUT/rows.txt" | sort | uniq -c | sort -rn
  echo "=== census by (tier, class) ==="
  awk '{t=$1; for(i=1;i<=NF;i++) if($i=="#299"){print t" "$(i+1); break}}' "$OUT/rows.txt" | sort | uniq -c | sort -rn
  echo "=== files with the most rows ==="
  awk '{print $1" "$2}' "$OUT/rows.txt" | sort | uniq -c | sort -rn | head -25
  echo "=== programs whose census channel saw a brand at all (brands>0) ==="
  grep -c 'brands=0 ' "$OUT/summaries.txt" | sed 's/^/  brandless programs: /'
  grep -v 'brands=0 ' "$OUT/summaries.txt" | wc -l | sed 's/^/  brand-declaring programs: /'
  echo "rows: $OUT/rows.txt   summaries: $OUT/summaries.txt"
}

neutral() {
  local BASE="$2" PROBE="$3"
  [ -x "$BASE" ] && [ -x "$PROBE" ] || { echo "brand_census: need two executables" >&2; exit 1; }
  local ddiag=0 dgas=0 n=0
  : > "$OUT/neutral.txt"
  while read -r f; do
    n=$((n+1))
    # (1) the CHECK path: exit status and the diagnostic bytes it writes.
    "$BASE"  check "$f" >"$OUT/b.out" 2>"$OUT/b.err"; local brc=$?
    "$PROBE" check "$f" >"$OUT/p.out" 2>"$OUT/p.err"; local prc=$?
    local bh ph
    bh=$(sha256sum < "$OUT/b.err" | cut -d' ' -f1)
    ph=$(sha256sum < "$OUT/p.err" | cut -d' ' -f1)
    if [ "$brc" != "$prc" ] || [ "$bh" != "$ph" ]; then
      ddiag=$((ddiag+1)); echo "DIAG $f base_rc=$brc probe_rc=$prc base_sha=$bh probe_sha=$ph" >> "$OUT/neutral.txt"
    fi
    # (2) the EMIT path: the GAS the two compilers produce for the SAME input, and its exit status.
    "$BASE"  "$f" >"$OUT/b.s" 2>/dev/null; local bg=$?
    "$PROBE" "$f" >"$OUT/p.s" 2>/dev/null; local pg=$?
    bh=$(sha256sum < "$OUT/b.s" | cut -d' ' -f1)
    ph=$(sha256sum < "$OUT/p.s" | cut -d' ' -f1)
    if [ "$bg" != "$pg" ] || [ "$bh" != "$ph" ]; then
      dgas=$((dgas+1)); echo "GAS  $f base_rc=$bg probe_rc=$pg base_sha=$bh probe_sha=$ph" >> "$OUT/neutral.txt"
    fi
  done < <(git ls-files 'test/*.al')
  echo "neutrality: fixtures=$n differing_diagnostics=$ddiag differing_gas=$dgas"
  sed 's/^/  /' "$OUT/neutral.txt"
  if [ "$ddiag" = 0 ] && [ "$dgas" = 0 ]; then
    echo "*** brand census: the probe build changes no exit status, no diagnostic byte and no emitted GAS byte ***"
    return 0
  fi
  return 1
}

# --- the instrument's own self-test -----------------------------------------------------------
#
# Every case below is a whole program written from here, never a tracked fixture: a self-test that
# reads the corpus proves the corpus, not the hook, and it goes quiet the moment the corpus changes.
# Each case is checked ALONE, because a brand refusal stops the check at the first failing
# declaration and a later crossing in the same program would then be silently unmeasured (measured:
# a module-level crossing above a function body suppressed every row inside the body).
PL_FAIL=0
PL_CASES=0

# `#299` rows only. The compiler opens other census channels on the same descriptor family and
# `grep '#299'` over an unfiltered file would count another instrument's work as this one's.
pl_rows() { grep '^#299 ' "$1" | grep -v ' SUMMARY '; }
pl_sinks() { sed -n 's/^#299 SUMMARY .* sinks=\([0-9]*\) .*/\1/p' "$1" | tail -1; }

# A case that MUST fire: at least `$3` rows, every one of class `$2`.
pl_crossing() { # $1 name  $2 class  $3 min-rows  (program on stdin)
  local name="$1" cls="$2" want="$3" f="$D/$name.al" r="$D/$name.rows" rc got bad
  cat > "$f"
  PL_CASES=$((PL_CASES+1))
  rc=$(probe_one "$CC" "$f" "$r")
  got=$(pl_rows "$r" | wc -l)
  bad=$(pl_rows "$r" | awk -v c="$cls" '$2!=c' | wc -l)
  if [ "$got" -ge "$want" ] && [ "$bad" = 0 ]; then
    printf '    %-22s PROVEN    rows=%-2s class=%-4s (check rc=%s)\n' "$name" "$got" "$cls" "$rc"
  else
    printf '    %-22s BLIND     rows=%-2s want>=%s of class %s, off-class=%s (check rc=%s)\n' \
      "$name" "$got" "$want" "$cls" "$bad" "$rc"
    pl_rows "$r" | sed 's/^/      seen: /'
    PL_FAIL=$((PL_FAIL+1))
  fi
}

# A case that must NOT fire, and must still have LOOKED: zero rows, `check` rc 0, and a `sinks=`
# count of at least `$2`. Without the third condition a hook that returns early scores exactly the
# same as a hook that visited every element and found them all legal.
pl_clean() { # $1 name  $2 min-sinks  (program on stdin)
  local name="$1" want="$2" f="$D/$name.al" r="$D/$name.rows" rc got sinks
  cat > "$f"
  PL_CASES=$((PL_CASES+1))
  rc=$(probe_one "$CC" "$f" "$r")
  got=$(pl_rows "$r" | wc -l)
  sinks=$(pl_sinks "$r")
  if [ "$rc" = 0 ] && [ "$got" = 0 ] && [ -n "$sinks" ] && [ "$sinks" -ge "$want" ]; then
    printf '    %-22s CLEAN     rows=0  sinks=%-2s (>=%s visited and judged legal, check rc=0)\n' \
      "$name" "$sinks" "$want"
  else
    printf '    %-22s BAD       rows=%s sinks=%s want rows=0 sinks>=%s rc=0, got rc=%s\n' \
      "$name" "$got" "${sinks:-none}" "$want" "$rc"
    pl_rows "$r" | sed 's/^/      seen: /'
    PL_FAIL=$((PL_FAIL+1))
  fi
}

planted() {
  CC="${2:-$ROOT/target/debug/alatyr}"
  [ -x "$CC" ] || { echo "brand_census: no compiler at $CC" >&2; exit 1; }
  D="$OUT/planted"; rm -rf "$D"; mkdir -p "$D"

  echo "=== planted crossings — which surface has been PROVEN able to produce a census row ==="
  echo "  SCALAR (the surface the census could always see; a regression guard, not the new claim):"
  pl_crossing scalar_b2 B2 1 <<'AL'
A := brand(u64)
B := brand(u64)
main := fn() -> u64 {
  b : B = B(2)
  x : A = b
  return u64(x)
}
AL

  echo "  ARRAY ELEMENT — both annotation spellings, the list and the [e; n] FILL form:"
  pl_crossing array_nt_list B2 2 <<'AL'
A := brand(u64)
B := brand(u64)
main := fn() -> u64 {
  b : B = B(2)
  xs : [2]A = [b, b]
  return u64(xs[0])
}
AL
  pl_crossing array_semi_list B2 3 <<'AL'
A := brand(u64)
B := brand(u64)
main := fn() -> u64 {
  b : B = B(2)
  xs : [A; 3] = [b, b, b]
  return u64(xs[0])
}
AL
  pl_crossing array_fill B2 2 <<'AL'
A := brand(u64)
B := brand(u64)
main := fn() -> u64 {
  b : B = B(2)
  xs : [2]A = [b; 2]
  return u64(xs[0])
}
AL

  echo "  ARRAY ELEMENT — every §4.2 class the classifier can answer, so a zero for one of them over"
  echo "  the real tree is a measurement and not a class the array walk cannot reach:"
  pl_crossing array_b1 B1 2 <<'AL'
A := brand(u64)
main := fn() -> u64 {
  n : u64 = 7
  xs : [2]A = [n, n]
  return u64(xs[0])
}
AL
  pl_crossing array_b1r B1R 2 <<'AL'
A := brand(u64)
main := fn() -> u64 {
  a : A = A(1)
  xs : [2]u64 = [a, a]
  return xs[0]
}
AL
  pl_crossing array_b3 B3 2 <<'AL'
A := brand(u64)
C := brand(u8)
main := fn() -> u64 {
  c : C = C(1)
  xs : [2]A = [c, c]
  return u64(xs[0])
}
AL

  echo "  ARRAY ELEMENT at the MODULE-LEVEL declaration sink (the #674 composition):"
  pl_crossing array_module B2 2 <<'AL'
A := brand(u64)
B := brand(u64)
G : [2]A = [B(1), B(2)]
main := fn() -> u64 { return u64(G[0]) }
AL

  echo
  echo "=== planted LEGAL programs — the other direction: no row, and proof the elements were seen ==="
  pl_clean array_legal 8 <<'AL'
A := brand(u64)
GL : [2]A = [A(1), A(2)]
main := fn() -> u64 {
  sc : A = A(1)
  xs : [3]A = [A(2), A(3), A(4)]
  ys : [A; 2] = [A(5), A(6)]
  return u64(sc) + u64(xs[0]) + u64(ys[1]) + u64(GL[0])
}
AL
  # Types §9.1/§9.2 give an integer literal its type from the annotation, so an all-literal array is
  # NOT a crossing — class B1U, which the refusal deliberately never touches. It is kept here as the
  # sharpest clean case there is: two visited element sinks, zero rows.
  pl_clean array_literal_elems 2 <<'AL'
A := brand(u64)
main := fn() -> u64 {
  xs : [2]A = [1, 2]
  return u64(xs[0])
}
AL

  echo
  echo "  planted cases=$PL_CASES  failures=$PL_FAIL"
  if [ "$PL_FAIL" = 0 ]; then
    echo "*** brand census: the counter fires on the SCALAR and the ARRAY-ELEMENT surface, in both"
    echo "    annotation spellings, in the fill form, across classes B1/B1R/B2/B3 and at the"
    echo "    module-level sink — and stays silent on a legal program whose elements it provably"
    echo "    visited. A zero from this instrument on those surfaces is a measurement. ***"
    return 0
  fi
  echo "*** brand census: $PL_FAIL of $PL_CASES planted cases did not behave — a zero from this"
  echo "    instrument on the affected surface would be MEANINGLESS until this passes ***"
  return 1
}

case "$MODE" in
  census)  census "$@" ;;
  neutral) neutral "$@" ;;
  planted) planted "$@" ;;
  *) echo "usage: brand_census.sh census|neutral|planted" >&2; exit 2 ;;
esac
