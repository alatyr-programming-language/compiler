#!/usr/bin/env bash
# scripts/full.sh — the AUTHORITATIVE integration gate for a src/ change.
#
# fixpoint (byte-for-byte self-reproduction: seed == Stage1 == Stage2) + the full e2e suite + the
# per-file four-backend CORPUS MANIFEST (scripts/corpus_manifest.sh: every tracked test/*.al on all four
# backends, ~1.5 min) + the `fmt` ARBITER over both corpora (scripts/fmt_corpus.sh: `run(fmt(x)) == run(x)`
# and `fmt(fmt(x)) == fmt(x)` over every tracked test/*.al, plus idempotence over the compiler's own
# src/+lib/ modules — the ONLY thing that sees a silent source rewrite, ~1 min at --jobs 8) + the IDIOM
# gate (scripts/idiom_gate.sh: a duplicate-DECISION detector against a reviewed baseline, ~2 s, no
# compiler needed) + the CONDITIONAL sweeps (scripts/sweeps.sh skips them for an x86-emit-only change). A skipped sweep is
# NOT a passed sweep: this script reads sweeps.sh's `STATUS=` line and says so in the verdict, so a
# GREEN gate can never be mistaken for one that exercised the non-x86 backends. Run this in the
# integration worktree before merging; a green result is the bar for landing a source change. For a
# reseed (seed != Stage1 expected), verify Stage2 == Stage3 separately (see "Reseed discipline" in AGENTS.md).
#
# Usage (inside `nix develop`):  bash scripts/full.sh [--force-sweeps] [<base-ref>]
#                                bash scripts/full.sh --self-test
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT" || exit 1

_full_gate_filter_guard() {
  if [ -n "${ALATYR_E2E_FILTER:-}" ]; then
    echo "FAIL: authoritative scripts/full.sh refuses non-empty ALATYR_E2E_FILTER; use scripts/e2e_fast.sh <filter> or run filtered scripts/e2e.sh directly." >&2
    return 2
  fi
  return 0
}

_full_gate_filter_self_test() {
  local _full_probe_output _full_probe_rc
  _full_probe_output="$(
    ALATYR_E2E_FILTER=__full_gate_filter_probe__ bash "$ROOT/scripts/full.sh" 2>&1
  )"
  _full_probe_rc=$?
  if [ "$_full_probe_rc" = 0 ]; then
    echo "FAIL full gate self-test: filtered full.sh invocation exited successfully" >&2
    return 1
  fi
  case "$_full_probe_output" in
    *"FULL GATE: GREEN"*)
      echo "FAIL full gate self-test: filtered invocation announced an authoritative green result" >&2
      return 1
      ;;
  esac
  if [ "$_full_probe_rc" != 2 ]; then
    echo "FAIL full gate self-test: filtered full.sh exited with $_full_probe_rc, want 2" >&2
    return 1
  fi
  case "$_full_probe_output" in
    *"ALATYR_E2E_FILTER"*"scripts/e2e_fast.sh"*"scripts/e2e.sh"*) ;;
    *)
      echo "FAIL full gate self-test: rejection did not name the filter and allowed iteration paths" >&2
      return 1
      ;;
  esac
  echo "ok   full gate self-test: non-empty ALATYR_E2E_FILTER is rejected before the gate"
}

_full_gate_filter_guard || exit $?
if [ "${1:-}" = "--self-test" ]; then
  _full_gate_filter_self_test
  exit $?
fi

echo "### FULL GATE SELF-TEST ###"
bash "$ROOT/scripts/full.sh" --self-test
_full_self_test_rc=$?
[ "$_full_self_test_rc" = 0 ] || { echo "  full gate self-test failed (rc=$_full_self_test_rc)"; exit 1; }

SWEEP_ARGS=()
if [ "${1:-}" = "--force-sweeps" ]; then SWEEP_ARGS+=(--force); shift; fi
[ -n "${1:-}" ] && SWEEP_ARGS+=("$1")

fail=0

# Logs live in this checkout's own target/, never a fixed /tmp path: every worktree runs this script, and a
# shared path means two lanes silently overwrite each other's evidence (and then read the other's).
LOGDIR="$ROOT/target"; mkdir -p "$LOGDIR"

echo "### CONTRACTS ###"
CONTRACT_LOG="$LOGDIR/full_contracts.log"
bash scripts/contract_check.sh > "$CONTRACT_LOG" 2>&1
contract_rc=$?
cat "$CONTRACT_LOG"
[ "$contract_rc" = 0 ] || fail=1
bash scripts/release_manifest_test.sh
[ "$?" = 0 ] || fail=1

FP_LOG="$LOGDIR/full_fp.log"; E2E_LOG="$LOGDIR/full_e2e.log"; CM_LOG="$LOGDIR/full_corpus_manifest.log"

echo "### FIXPOINT ###"
bash scripts/fixpoint.sh > "$FP_LOG" 2>&1
grep -iE "TOOL-1 FIXPOINT|FAIL" "$FP_LOG"
grep -q "TOOL-1 FIXPOINT: seed == Stage1 == Stage2" "$FP_LOG" || { echo "  (fixpoint NOT green — a reseed change needs the 3-stage check; see \"Reseed discipline\" in AGENTS.md)"; fail=1; }

echo "### E2E ###"
bash scripts/e2e.sh > "$E2E_LOG" 2>&1
grep -iE "\*\*\* e2e" "$E2E_LOG"
grep -q "\*\*\* e2e: all green \*\*\*" "$E2E_LOG" || { echo "  FAILURES:"; grep -i "^FAIL" "$E2E_LOG" | head; fail=1; }

# The corpus manifest is UNCONDITIONAL, and that is deliberate. The sweeps may skip because an
# x86-emit-only change provably cannot alter non-x86 output; no such argument exists for the manifest,
# whose x86_64 column is exactly what an x86 emitter refactor moves. It reuses the compiler this gate
# already built (fixpoint.sh leaves Stage2 in target/debug/alatyr, and the script refuses one older than
# src/|lib/), logs into this checkout's own target/, and prints its own gate-of-the-gate.
echo "### CORPUS MANIFEST ###"
bash scripts/corpus_manifest.sh --check > "$CM_LOG" 2>&1
cm_rc=$?
grep -E "^corpus manifest: (  sha256|detector|rows=|match|MISMATCH|WROTE)" "$CM_LOG"
cm_cover="$(grep -E "^corpus manifest: rows=" "$CM_LOG" | tail -1 | sed 's/^corpus manifest: //')"
if [ "$cm_rc" != 0 ]; then
  echo "  FAILURES (tail of $CM_LOG):"; tail -30 "$CM_LOG" | sed 's/^/    /'
  fail=1
fi
# A manifest that printed no coverage line exercised nothing we can name; that must not read as a pass.
if [ -z "$cm_cover" ]; then
  echo "  (scripts/corpus_manifest.sh printed no 'rows=' coverage line — what it observed is unknown,"
  echo "   treating as a failure)"
  fail=1; cm_cover="UNKNOWN — no coverage line"
fi

# The `fmt` ARBITER. `alatyr fmt` has NO fail-loud channel for a wrong RENDERING — it exits 0 and
# writes source — so a mis-rendered form is a SILENT MISCOMPILE of the user's own program, and this is
# the only gate that can see it. Two walks: the test corpus (behaviour AND idempotence) and the
# compiler's own src/+lib/ modules (idempotence only — a module has no `_start`, so there is nothing to
# run). The second walk is not optional politeness: `fmt` was non-idempotent on SIX of these modules
# while every other gate stayed green, and on the `deref(p) = v` shape the reparse dropped the STORE.
# It logs into this checkout's target/, and the compiler it uses is the Stage1 SNAPSHOT the E2E step
# above left at target/e2e/cc/bin/alatyr — not target/debug/alatyr, which the fixpoint step leaves
# behind but which a later `build` in this same checkout would replace under us. That makes this step
# ORDER-DEPENDENT on the E2E step: fmt_corpus.sh honours $ALATYR and fails loud when it is absent
# (it falls back to target/debug/alatyr only when $ALATYR is unset), so a reordering breaks visibly
# rather than measuring a different compiler than the one the row counts above belong to.
echo "### FMT CORPUS (fmt arbiter: test/ programs + src/ & lib/ modules) ###"
FC_LOG="$LOGDIR/full_fmt_corpus.log"
ALATYR="$ROOT/target/e2e/cc/bin/alatyr" bash scripts/fmt_corpus.sh --jobs 8 > "$FC_LOG" 2>&1
fc_rc=$?
grep -E "^(fmt corpus walk=|\*\*\* fmt corpus)" "$FC_LOG"
fc_cover="$(grep -cE "^fmt corpus walk=" "$FC_LOG")"
fc_line="$(grep -E "^fmt corpus walk=" "$FC_LOG" | tr '\n' '|' | sed 's/|$//')"
if [ "$fc_rc" != 0 ]; then
  echo "  FAILURES (from $FC_LOG):"; grep -E "^REGRESSION" "$FC_LOG" | head -20 | sed 's/^/    /'
  fail=1
fi
# TWO walks must each print a coverage line. One line means a walk was skipped and the green would be
# reporting on half the input.
if [ "$fc_cover" != 2 ]; then
  echo "  (scripts/fmt_corpus.sh printed $fc_cover of 2 expected 'fmt corpus walk=' coverage lines —"
  echo "   one of the two walks did not report, so what it observed is unknown; treating as a failure)"
  fail=1
fi

# The IDIOM gate. REPORTING ONLY, and it needs no compiler — a pure source scan, so it can never
# collide with another lane over target/debug/alatyr. It fails only on a duplicate decision that is NOT in
# scripts/idiom.baseline, and it runs its own gate-of-the-gate first (five planted defects that every
# rule must fire on, and a clean twin that none may fire on) — so a green here means the detector was
# alive when it said so.
echo "### IDIOM (duplicate-decision detector, reporting only) ###"
IG_LOG="$LOGDIR/full_idiom.log"
bash scripts/idiom_gate.sh > "$IG_LOG" 2>&1
ig_rc=$?
grep -E "^(idiom: gate-of-the-gate|idiom gate:|\*\*\* idiom gate)" "$IG_LOG"
ig_cover="$(grep -cE "^idiom gate: files=" "$IG_LOG")"
ig_line="$(grep -E "^idiom gate: (files|stride-sites)=" "$IG_LOG" | tail -1)"
if [ "$ig_rc" != 0 ]; then
  echo "  FAILURES (from $IG_LOG):"; grep -E "^  NEW |^idiom: FAIL" "$IG_LOG" | head -20 | sed 's/^/    /'
  fail=1
fi
if [ "$ig_cover" != 1 ]; then
  echo "  (scripts/idiom_gate.sh printed no 'idiom gate: files=' proof-of-work line — what it walked is"
  echo "   unknown, treating as a failure)"
  fail=1
fi

echo "### SWEEPS (conditional) ###"
bash scripts/sweeps.sh "${SWEEP_ARGS[@]}" 2>&1 | tee "$LOGDIR/full_sweeps.log"
[ "${PIPESTATUS[0]}" = 0 ] || fail=1
sw_status="$(grep -oE '^sweeps: STATUS=[A-Z]+' "$LOGDIR/full_sweeps.log" | tail -1 | cut -d= -f2)"
if [ -z "$sw_status" ]; then
  echo "  (scripts/sweeps.sh printed no STATUS line — the sweep outcome is unknown, treating as a failure)"
  fail=1; sw_status=UNKNOWN
fi

if [ "$fail" != 0 ]; then
  echo "*** FULL GATE: FAILURES ***"
elif [ "$sw_status" = "RAN" ]; then
  echo "*** FULL GATE: GREEN (sweeps RAN) ***"
  echo "    corpus manifest: $cm_cover"
  echo "    fmt arbiter:     ${fc_line:-NO COVERAGE LINE}"
  echo "    idiom gate:      ${ig_line:-NO COVERAGE LINE}"
else
  echo "*** FULL GATE: GREEN — but the SWEEPS DID NOT RUN (sweeps STATUS=$sw_status): the aarch64/"
  echo "    riscv64/wasm backends were NOT exercised by the sweeps. Re-run with --force-sweeps before"
  echo "    landing any change that can reach a backend. ***"
  echo "    corpus manifest: $cm_cover"
  echo "    fmt arbiter:     ${fc_line:-NO COVERAGE LINE}"
  echo "    idiom gate:      ${ig_line:-NO COVERAGE LINE}"
fi
exit "$fail"
