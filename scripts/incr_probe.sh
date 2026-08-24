#!/usr/bin/env bash
# scripts/incr_probe.sh — the measurement harness behind the INCREMENTAL-COMPILATION plan (TOOL-6).
#
# It answers three questions with numbers, not adjectives:
#
#   profile   Where does a self-build's wall time actually go? Splits the build into
#             front-end+sema / emit / as+ld by timing the three CLI modes that bracket them
#             (`check` = read+lex+parse+sema, `<manifest>` = + emit_program, `build` = + as+ld),
#             then (if `perf` is on PATH) attributes the emit share by direct callee of
#             `lower__emit_program` — the DCE / per-module `.text` / monomorphized-instances split.
#
#   blast     How many modules does a one-file edit actually invalidate? Uses the per-module
#             `.o` SPLIT (`ALATYR_OSPLIT=1`, which writes one `<out>.<i>.s` per module) as a
#             free per-module emission fingerprint: snapshot every span's sha256, apply an edit,
#             re-emit, and diff. This is the fraction an emit cache could reuse. Six probes, each
#             with the radius it MUST have; a probe off its expected radius fails the mode.
#             It is the acceptance gate for the module-local label namespace (`lower::MODTAB`):
#             before it, ONE added string literal renumbered `.Lstr` in 13 of the 19 blocks.
#
#   split     Re-run the per-module `.o` split gate: fixpoint + full e2e under `ALATYR_OSPLIT=1`,
#             twice (the fault it was parked for was believed layout-sensitive; it was in fact a
#             64-byte name StrBuf overflowing for any output path >= 54 chars — see `link_exe_split`).
#             The fixpoint line is only meaningful once `seed/` matches `src/`; across a pending
#             reseed it reads DIFFER for the seed-vs-Stage1 leg by construction.
#
# Usage (inside `nix develop`):  bash scripts/incr_probe.sh [profile|blast|split|all]
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT" || exit 1
ulimit -c 0
MODE="${1:-all}"
M="$ROOT/package.al"
mkdir -p target

## Scratch lives in this checkout's own target/, never a fixed path under the shared temp directory:
## every worktree runs this script, and a shared path means two probes read each other's snapshots
## and then attribute the difference to their own edit. (scripts/full.sh states the same rule.)
WORK="$ROOT/target/incr"; mkdir -p "$WORK"

## `debug` is the default build profile, so the manifest's output is target/debug/alatyr; the legacy
## flat target/alatyr is accepted for a tree mid-transition, exactly as fixpoint.sh and dev.sh do.
## OUT is where the BUILD lands (and therefore where ALATYR_OSPLIT writes its per-module `.s`/`.o`
## and the emission manifest); CC is the compiler DRIVING the build. They are not the same file:
## `build` replaces OUT, so a measurement must be driven by a frozen copy taken beforehand.
resolve_out() {
  if [ -x "$ROOT/target/debug/alatyr" ]; then OUT="$ROOT/target/debug/alatyr"
  elif [ -x "$ROOT/target/alatyr" ]; then OUT="$ROOT/target/alatyr"
  else OUT=""; fi
}
resolve_out
CC="$OUT"

build_stage1() {
  if [ -z "$OUT" ]; then
    echo "--- building Stage1 (seed builds the tree) ---"
    "$ROOT/seed/alatyr" build "$M" >/dev/null 2>&1 || { echo "FAIL: seed build"; exit 1; }
    resolve_out
  fi
  ## Fail LOUD rather than measure nothing. `t()` redirects the timed command's output to /dev/null,
  ## so a missing compiler would be timed as a ~0.00 s "build" and reported as a result — the silent
  ## wrong number this repository treats as the one forbidden outcome. This guard is why the path is
  ## resolved above instead of hard-coded: the flat target/alatyr stopped being the build output when
  ## the profile directory landed, and a stale leftover from an older build is what hid it.
  [ -n "$OUT" ] && [ -x "$OUT" ] || { echo "FAIL: no compiler at target/debug/alatyr (nor legacy target/alatyr)"; exit 1; }
  ## `build` REPLACES $OUT, so measure with a frozen copy of the compiler. That copy MUST sit directly
  ## under target/ and nowhere deeper: `lib_dir` is `dirname(/proc/self/exe)/../lib`, so target/incr_cc
  ## resolves the stdlib to the real ./lib while target/incr/incr_cc resolves it to a target/lib that
  ## does not exist. Measured, one directory deeper: `check package.al` returned rc 1 in 0.30 s with
  ## "selfhost: cannot open source file" instead of rc 0 in 13.6 s — and `t()` reported that 0.30 s as
  ## the front-end phase, making `emit` come out NEGATIVE. Do not move this file into $WORK.
  cp "$OUT" "$ROOT/target/incr_cc" || { echo "FAIL: could not snapshot $OUT"; exit 1; }
  CC="$ROOT/target/incr_cc"
  ## Prove the frozen copy can do the very work about to be timed. A binary that exists but cannot
  ## find its stdlib still EXITS, fast, and `t()` cannot tell that apart from a fast compiler.
  if ! "$CC" check "$M" >/dev/null 2>"$WORK/precheck.err"; then
    echo "FAIL: the frozen compiler at $CC cannot compile $M — every timing below would be a failure's"
    echo "      duration, not a phase's. First lines of its stderr:"
    sed 's/^/      /' "$WORK/precheck.err" | head -3
    exit 1
  fi
}

t() { # t <label> <cmd...>  — wall seconds, 3 runs, min reported
  local label="$1"; shift
  local best=999999 s e d rc
  for _ in 1 2 3; do
    s=$(date +%s.%N); "$@" >/dev/null 2>"$WORK/t.err"; rc=$?; e=$(date +%s.%N)
    ## A FAILING command has a duration too, and reporting it as a phase time is how this harness
    ## once printed a negative `emit` share: the timed compiler was exiting 1 in 0.3 s. Never time
    ## a failure silently.
    if [ "$rc" != 0 ]; then
      echo "FAIL: '$label' exited $rc — its duration is not a phase measurement. Its stderr:" >&2
      sed 's/^/      /' "$WORK/t.err" | head -3 >&2
      exit 1
    fi
    d=$(echo "$e - $s" | bc)
    best=$(echo "if ($d < $best) $d else $best" | bc)
  done
  ## printed to stderr so the caller can capture the bare number on stdout (locale-proof: no printf %f)
  echo "  $label  ${best} s" >&2
  echo "$best"
}

do_profile() {
  build_stage1
  echo "=== PHASE PROFILE (min of 3 runs) ==="
  local tc tg tb
  tc=$(t "check   (read+lex+parse+sema)" "$CC" check "$M" | tail -1)
  tg=$(t "gas     (+ emit_program)"      "$CC" "$M"       | tail -1)
  tb=$(t "build   (+ as + ld)"           "$CC" build "$M" | tail -1)
  echo "---"
  echo "  front-end+sema : $tc s"
  echo "  emit           : $(echo "$tg - $tc" | bc) s"
  echo "  as+ld          : $(echo "$tb - $tg" | bc) s"
  echo "  total build    : $tb s"
  command -v perf >/dev/null 2>&1 || { echo "(perf absent — skipping the emit-phase attribution)"; return; }
  echo
  echo "=== emit_program attribution (perf, frame-pointer call graph) ==="
  perf record -F 499 --call-graph=fp -o target/incr_perf.data -- "$CC" "$M" >/dev/null 2>&1
  perf report -i target/incr_perf.data --stdio --children --sort=symbol --percent-limit=1 2>/dev/null \
    | grep -E '^ +[0-9].*(emit_program|emit_fn|mark_calls_stmts|collect_insts|check_program|parse_program|peephole)' || true
}

# --- the per-module emission fingerprint (needs the split enabled) -------------------------------
## The fingerprint comes from the EMISSION MANIFEST, not from globbing the split's `.s` files.
##
## It used to glob `<out>.<i>.s`, and that shape stopped existing: the split now writes
## `<dir-of-out>/<module>__<i>.s` (plus `alatyr__<i>.s`, `instances__<i>.s` and, for spans whose
## module could not be named, `<unmapped-module>__<i>.s`). Measured, the stale glob matched nothing,
## so every probe read a 0-span snapshot — `blast` then reported "only 0 span(s)" rather than a wrong
## radius, which is the one thing that went right here.
##
## The manifest is the better source anyway: `manifest_gate` above already proves it is deterministic
## across two cold builds, each `span=` record already carries a `gas_hash`, and the key is the span's
## `input=` rather than a FILENAME carrying an index that shifts when a module is added. Duplicate
## inputs (`<unmapped-module>` occurs many times) get an occurrence suffix so `join` still sees unique
## keys, which is why this projects rather than just cutting two fields.
spans_snapshot() { # spans_snapshot <file>
  rm -f "$(dirname "$OUT")"/*__[0-9]*.s "$(dirname "$OUT")"/*__[0-9]*.o "$OUT".manifest
  ALATYR_OSPLIT=1 "$CC" build "$M" >/dev/null 2>&1
  : > "$1"
  [ -s "$OUT".manifest ] || return 0
  gawk '
    /^span=/ {
      hash = ""; input = ""
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^gas_hash=/) { hash = substr($i, 10) }
        else if ($i ~ /^input=/) { input = substr($i, 7) }
      }
      if (input == "" || hash == "") next
      key = input
      if (input in seen) { key = input "#" ++seen[input] } else { seen[input] = 1 }
      print key, hash
    }' "$OUT".manifest | LC_ALL=C sort > "$1"
}

manifest_snapshot() { # manifest_snapshot <file>
  rm -f "$(dirname "$OUT")"/*__[0-9]*.s "$(dirname "$OUT")"/*__[0-9]*.o "$OUT".manifest
  ALATYR_OSPLIT=1 "$CC" build "$M" >/dev/null 2>&1
  [ -s "$OUT".manifest ] || {
    echo "FAIL: split build did not write $OUT.manifest"
    return 1
  }
  cp "$OUT".manifest "$1"
}

manifest_gate() {
  echo "=== PER-MODULE MANIFEST GATE (two cold split builds) ==="
  manifest_snapshot "$WORK/manifest_a" || return 1
  manifest_snapshot "$WORK/manifest_b" || return 1
  if ! cmp -s "$WORK/manifest_a" "$WORK/manifest_b"; then
    echo "FAIL: cold split builds produced different emission manifests"
    return 1
  fi
  grep -q '^format=alatyr-emission-manifest$' "$WORK/manifest_a" || {
    echo "FAIL: emission manifest format marker missing"
    return 1
  }
  grep -q '^hash=fnv1a64$' "$WORK/manifest_a" || {
    echo "FAIL: emission manifest hash algorithm missing"
    return 1
  }
  local spans modules
  spans=$(sed -n 's/^span_count=//p' "$WORK/manifest_a")
  modules=$(grep -c '^span=.* kind=module ' "$WORK/manifest_a")
  [ -n "$spans" ] && [ "$spans" -gt 1 ] && [ "$modules" -eq $((spans - 1)) ] || {
    echo "FAIL: emission manifest span/module cardinality is inconsistent"
    return 1
  }
  grep -q 'kind=instances .*input=<monomorphized-instances>$' "$WORK/manifest_a" || {
    echo "FAIL: emission manifest instances span is not explicit"
    return 1
  }
  echo "  *** manifest: deterministic, hashed, and module-complete ***"
}

do_blast() {
  build_stage1
  echo "=== INVALIDATION BLAST RADIUS (per-module GAS blocks) ==="
  manifest_gate || return 1
  spans_snapshot "$WORK/base.txt"
  local n; n=$(wc -l < "$WORK/base.txt")
  if [ "$n" -le 1 ]; then
    echo "FAIL: only $n span(s) — the per-module split did not run, or it wrote no emission manifest."
    echo "      $OUT must be a build of a tree whose link_exe_split is enabled, and"
    echo "      $OUT.manifest must carry its span= records."
    return 1
  fi
  echo "  $n per-module GAS blocks"
  ## Every probe EDITS a source file, re-emits, diffs the per-module fingerprints, and RESTORES the
  ## file from a backup (the tree is never left modified, even on a failed build). Two probe shapes:
  ##   probe_edit    — an in-place `sed` rewrite
  ##   probe_append  — append a line at EOF (the only way to ADD a top-level string literal cleanly)
  local rc=0
  probe_run() { # probe_run <label> <file> <expect> <mutator...>
    local label="$1" file="$2" expect="$3"; shift 3
    cp "$file" "$WORK/edit.bak"
    "$@"
    ## A probe whose mutation MATCHED NOTHING measures nothing, and its radius of 0 is
    ## indistinguishable from "the compiler now invalidates nothing" — which reads as a WIN against an
    ## expectation of 4. `probe_edit` is a `sed` against a literal spelling in src/, so it goes stale
    ## silently every time that line is reworded. Say which of the two happened.
    if cmp -s "$WORK/edit.bak" "$file"; then
      cp "$WORK/edit.bak" "$file"
      printf '  %-46s %s\n' "$label" "STALE PROBE — the mutation matched nothing; no radius was measured"
      rc=1
      return
    fi
    spans_snapshot "$WORK/edit.txt"
    cp "$WORK/edit.bak" "$file"
    local changed cnt verdict
    changed=$(join "$WORK/base.txt" "$WORK/edit.txt" | awk '$2!=$3 {print $1}' | tr '\n' ' ')
    cnt=$(join "$WORK/base.txt" "$WORK/edit.txt" | awk '$2!=$3' | wc -l)
    verdict=ok; [ "$cnt" = "$expect" ] || { verdict="WANT $expect"; rc=1; }
    printf '  %-46s %2d block(s)  [%s]  %s\n' "$label" "$cnt" "$verdict" "${changed:-<none>}"
  }
  probe_edit()   { sed -i "$2" "$1"; }
  probe_append() { printf '\n%s\n' "$2" >> "$1"; }

  ## 1-2. an ordinary BODY edit — the module's own block, nothing else.
  probe_run "body edit in rt.al (string literal)"      src/rt.al    1 \
    probe_edit src/rt.al    's/rt: StrBuf overflow/rt: StrBuf overflowZ/'
  probe_run "body edit in lower.al (numeric constant)" src/lower.al 1 \
    probe_edit src/lower.al '0,/if insts >= 60 { return false }/s//if insts >= 61 { return false }/'
  ## 3-4. a COMMENT lengthened — every following byte offset in the concatenated source buffer shifts.
  ## Must be 0: no emitted label may be keyed on an ABSOLUTE source offset. (`.Lflt`/`.Lfld` are keyed
  ## on offsets, but MODULE-RELATIVE ones; a lifted lambda's `<module>__lam<fnpos>` is the one absolute
  ## key left — it is dormant in the self-build, so these two probes do not cover it.)
  probe_run "comment lengthened in driver.al (offsets)" src/driver.al 0 \
    probe_edit src/driver.al '0,/^## /s//## X /'
  probe_run "comment lengthened in ast.al (offsets)"    src/ast.al    0 \
    probe_edit src/ast.al    '0,/^## /s//## X /'
  ## 5. a LAYOUT change — genuinely invalidates the type's USERS (a real, irreducible dependency).
  probe_run "LAYOUT edit in ast.al (extra field)"      src/ast.al   4 \
    probe_edit src/ast.al   's/pub LocalTypeSpan := struct { s : usize, n : usize }/pub LocalTypeSpan := struct { s : usize, n : usize, pad_probe : usize }/'
  ## 6. THE ONE THAT MATTERED. A string literal ADDED to driver.al (module 4). The `.Lstr` label index
  ## used to be a SINGLE parse-order counter threaded across every module, so one added literal
  ## renumbered every `.Lstr` downstream of it — 13 of the 19 blocks (all of modules 4..17 that carry
  ## any `.Lstr` at all; `main` and the instances block carry none, so they can never be in the set).
  ## With per-module `.Lstr<m>_<n>` labels only driver's own block moves: 13 -> 1.
  probe_run "string literal ADDED to driver.al (mod 4)" src/driver.al 1 \
    probe_append src/driver.al '_incr_probe_lit := "zz"'
  rm -f "$(dirname "$OUT")"/*__[0-9]*.s "$(dirname "$OUT")"/*__[0-9]*.o
  [ "$rc" = 0 ] && echo "  *** blast: every probe at its expected radius ***" \
                || echo "  *** blast: a probe is OFF its expected radius ***"
  return "$rc"
}

do_split() {
  echo "=== PER-MODULE .o SPLIT GATE (ALATYR_OSPLIT=1, two rounds) ==="
  export ALATYR_OSPLIT=1
  local r
  for r in 1 2; do
    bash scripts/fixpoint.sh 2>&1 | grep -E 'TOOL-1 FIXPOINT|DIFFER|FAIL' | sed "s/^/  round $r fixpoint: /"
    bash scripts/e2e.sh > "$WORK/e2e_$r.log" 2>&1
    echo "  round $r e2e: ok=$(grep -c '^ok' "$WORK/e2e_$r.log") FAIL=$(grep -c '^FAIL' "$WORK/e2e_$r.log")"
  done
}

case "$MODE" in
  profile) do_profile ;;
  blast)   do_blast ;;
  split)   do_split ;;
  all)     do_profile; echo; do_blast; echo; do_split ;;
  *)       echo "usage: $0 [profile|blast|split|all]"; exit 2 ;;
esac
