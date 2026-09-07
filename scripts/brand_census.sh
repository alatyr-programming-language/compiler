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
#
# `census` prints a per-class total, a per-file breakdown and, for every row, the source line the
# instrument saw. `neutral` is the companion the #507 caveat requires: an instrumented census can
# report confidently and wrongly, so the claim "this build only counts" is proved separately, by
# comparing every tracked fixture's exit status and normalized diagnostic bytes between the two
# compilers with the input tree held fixed.
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

case "$MODE" in
  census)  census "$@" ;;
  neutral) neutral "$@" ;;
  *) echo "usage: brand_census.sh census|neutral" >&2; exit 2 ;;
esac
