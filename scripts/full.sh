#!/usr/bin/env bash
# scripts/full.sh — the AUTHORITATIVE integration gate for a src/ change.
#
# The INPUT-SET check first (scripts/corpus_enum_check.sh: the git index and the worktree must name
# the same `.al` corpus, 0.085 s measured, no compiler needed — a fixture that is written but never `git
# add`ed is invisible to the two oracle stages and visible to e2e and all three sweeps, and no later
# stage can see that, issue #645). Then the SPEC-PIN join (scripts/spec_pin_check.sh: the five places
# that state the specification revision — `src/spec_revision.al`, README.md, AGENTS.md "The pin",
# scripts/package_cli_test.sh's expected `--version` line, seed/VERSION — must name ONE number, no
# compiler needed, issue #1000). Then fixpoint (byte-for-byte self-reproduction: seed == Stage1 == Stage2) + the full e2e suite + the
# per-file four-backend CORPUS MANIFEST (scripts/corpus_manifest.sh: every tracked test/*.al on all four
# backends, ~1.5 min) + the `fmt` ARBITER over both corpora (scripts/fmt_corpus.sh: `run(fmt(x)) == run(x)`
# and `fmt(fmt(x)) == fmt(x)` over every tracked test/*.al, plus idempotence over the compiler's own
# src/+lib/ modules — the ONLY thing that sees a silent source rewrite, ~1 min at --jobs 8) + the IDIOM
# gate (scripts/idiom_gate.sh: a duplicate-DECISION detector against a reviewed baseline, ~2 s, no
# compiler needed) + the CONDITIONAL sweeps (scripts/sweeps.sh skips them for an x86-emit-only change). A skipped sweep is
# NOT a passed sweep: this script reads sweeps.sh's `STATUS=` line and says so in the verdict, so a
# GREEN gate can never be mistaken for one that exercised the non-x86 backends. Run this in the
# integration worktree before merging; a green result is the bar for landing a source change. For a
# reseed (seed != Stage1 expected), verify Stage2 == Stage3 separately (see "Reproducibility" in AGENTS.md).
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
  _full_gate_filter_self_test_rc=$?
  [ "$_full_gate_filter_self_test_rc" = 0 ] || exit "$_full_gate_filter_self_test_rc"
  # The INPUT-SET decider's gate-of-the-gate (issue #645). It belongs here, with the gate's other
  # self-tests, for the reason that issue records: on a healthy tree the enumeration check never
  # reaches its own failure verdict, so a neutered decider would go on printing a green line for
  # ever. Eleven planted trees drive the decider directly, and four of them are CONTROLS that must
  # stay green, so a decider that simply always failed would score zero here rather than full marks.
  bash "$ROOT/scripts/corpus_enum_check.sh" --self-test
  _full_corpus_enum_self_test_rc=$?
  [ "$_full_corpus_enum_self_test_rc" = 0 ] || exit "$_full_corpus_enum_self_test_rc"
  # The WILDCARD-ARM decider's gate-of-the-gate (issue #658, the #600 rule). Same reason as the one
  # above it: on a tree that adds no wildcard arm the check never reaches its own failure verdict, so
  # a neutered decider would print a green line for ever. Eleven planted trees drive the decider
  # directly, and FIVE of them are controls that must stay green — an unchanged tree, a removal, an
  # acknowledged arm, the integer/comptime exemptions, and an arm quoted in prose — so a decider that
  # simply always failed scores zero here rather than full marks. Measured: an always-pass decider
  # loses the five addition cases, an always-fail decider loses the five controls, and a scanner that
  # stops skipping comments loses the prose control.
  bash "$ROOT/scripts/wildcard_arm_check.sh" --self-test
  _full_wildcard_self_test_rc=$?
  [ "$_full_wildcard_self_test_rc" = 0 ] || exit "$_full_wildcard_self_test_rc"
  # The STRICT-FORMS decider's gate-of-the-gate (issue #691, the #600 rule), for the wildcard check's
  # reason: on a tree that adds no strict form the check never reaches its own failure verdict. Every
  # rule is refused by name on a planted addition, every escape marker is proved to work, and the
  # controls (an unchanged tree, a removal and a move between files, acknowledged forms, forms quoted
  # in prose and strings) must stay green — so an always-pass decider loses the plants, an always-fail
  # decider loses the controls, and a scanner that stops skipping comments loses the prose control.
  bash "$ROOT/scripts/strict_forms_check.sh" --self-test
  _full_strict_self_test_rc=$?
  [ "$_full_strict_self_test_rc" = 0 ] || exit "$_full_strict_self_test_rc"
  # The SEED-FORMS registry's gate-of-the-gate (strict_forms.md §8, the #600 rule). On a tree whose
  # seed still miscompiles every registered form, the check never reaches its own failure verdicts:
  # a form regressed in the tree, the seed now handling a form (the retirement signal), or the tree
  # now handling a `tree` row. So thirteen planted registries drive it with a fake compiler, and three
  # of them are CONTROLS that must stay green. Measured: an always-OK decider loses the three verdict
  # plants, an always-failing decider loses the three controls, and dropping the orphan walk loses
  # the orphan plant.
  bash "$ROOT/scripts/seed_forms_check.sh" --self-test
  _full_seed_forms_self_test_rc=$?
  [ "$_full_seed_forms_self_test_rc" = 0 ] || exit "$_full_seed_forms_self_test_rc"
  # The SPEC-PIN decider's gate-of-the-gate (issue #1000), for the enumeration check's reason: on a tree
  # that agrees, the pin check never reaches its own failure verdict, so a neutered decider would print
  # the same green line forever. Thirteen planted trees drive it — FOUR controls that must stay green (two
  # of them the halves that must SKIP out loud rather than pass quietly), SIX disagreements each named
  # with both numbers, and THREE refusals for a constant that is absent, doubled or malformed.
  bash "$ROOT/scripts/spec_pin_check_test.sh"
  _full_spec_pin_self_test_rc=$?
  [ "$_full_spec_pin_self_test_rc" = 0 ] || exit "$_full_spec_pin_self_test_rc"
  # AGENTS.md's line limit (#1130): a decider that never refuses would print the same green line forever.
  bash "$ROOT/scripts/agents_size_check.sh" --self-test
  _full_agents_size_self_test_rc=$?
  [ "$_full_agents_size_self_test_rc" = 0 ] || exit "$_full_agents_size_self_test_rc"
  # The scripted seed promotion's deciders (#1129): the version order, the label normalization, the
  # convergence verdict, the bump, the owed-marker and atomic-set refusals and the cadence. Measured:
  # a convergence check that ignores the binary, or a cadence that reads gh's silence as "not due",
  # loses its plant.
  bash "$ROOT/scripts/promote.sh" --self-test
  _full_promote_self_test_rc=$?
  [ "$_full_promote_self_test_rc" = 0 ] || exit "$_full_promote_self_test_rc"
  bash "$ROOT/scripts/land.sh" --self-test
  _full_land_self_test_rc=$?
  [ "$_full_land_self_test_rc" = 0 ] || exit "$_full_land_self_test_rc"
  # The progen nightly's issue hook (#1128): which backend a finding blames, and open / comment /
  # reopen on its marker. A hook nobody has seen decide is a hook that opens nothing on a red night.
  python3 "$ROOT/scripts/progen_report.py" --self-test || exit 1
  # The merge queue's deciders (#1127): the reviewed-head marker and the bisection plan, against a
  # fake gate in which one PR of three is red. Measured: a driver that drops the rest of a split set
  # loses the plan checks; taking the first marker instead of the last loses the marker check.
  bash "$ROOT/scripts/queue.sh" --self-test
  _full_queue_self_test_rc=$?
  [ "$_full_queue_self_test_rc" = 0 ] || exit "$_full_queue_self_test_rc"
  # The weekly report's two local deciders (#1131): the lead-time median and the header-versus-x86_64-row
  # comparison. The report itself needs `gh` and runs on a workstation, so nothing in the gate would
  # otherwise execute it; eight planted inputs, including a prose header that must NOT be compared and an
  # aarch64 row that must not count as x86_64, keep the deciders honest without the network.
  bash "$ROOT/scripts/metrics.sh" --self-test
  _full_metrics_self_test_rc=$?
  [ "$_full_metrics_self_test_rc" = 0 ] || exit "$_full_metrics_self_test_rc"
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
FP_LOG="$LOGDIR/full_fp.log"; E2E_LOG="$LOGDIR/full_e2e.log"; CM_LOG="$LOGDIR/full_corpus_manifest.log"

# The INPUT-SET check, and it runs FIRST on purpose. Every stage below enumerates its input either
# from the git INDEX (corpus manifest, both fmt walks) or from the WORKTREE (e2e, the three sweeps,
# the compiler build), and a fixture that is written but never `git add`ed exists for the second
# group and not for the first. That is not a stage failure anywhere: the corpus oracle's row-count
# identity (`rows == sources × 4 − excluded`) is computed from the same index enumeration as the
# rows, so both sides shrink together and the gate goes GREEN describing a corpus it never saw
# (measured by the #422 lane at rows=8208; issue #645). Nothing after this line can detect it, so
# the divergence is refused here and the gate STOPS — running six minutes of stages over an input
# set nobody chose produces evidence that must not be read.
echo "### CORPUS ENUMERATION (git index vs worktree) ###"
CE_LOG="$LOGDIR/full_corpus_enum.log"
bash scripts/corpus_enum_check.sh > "$CE_LOG" 2>&1
ce_rc=$?
cat "$CE_LOG"
ce_cover="$(grep -E "^corpus enum: index=" "$CE_LOG" | tail -1 | sed 's/^corpus enum: //')"
if [ "$ce_rc" != 0 ]; then
  echo "*** FULL GATE: REFUSED before any stage ran — the git index and the worktree do not name the"
  echo "    same .al corpus (see above). The oracle stages and the executing stages would describe"
  echo "    different trees, and a GREEN verdict from this run would be meaningless. ***"
  exit 1
fi
# A check that printed no counts cannot be told apart from one that enumerated nothing.
if [ -z "$ce_cover" ]; then
  echo "*** FULL GATE: REFUSED — scripts/corpus_enum_check.sh printed no 'index=' coverage line, so"
  echo "    what it compared is unknown. ***"
  exit 1
fi

# The SPEC-PIN check (issue #1000). A text join over the five places this repository states one number —
# `src/spec_revision.al`, README.md, AGENTS.md "The pin", scripts/package_cli_test.sh's expected
# `--version` line, and seed/VERSION's CURRENT SEED note — so it needs no compiler and costs well under a
# second, which is why it sits here with the other cheap pre-build stages rather than after six minutes of
# building. TOOL-21 makes `version` report the specification revision it conforms to; this is what stops
# that reported number from being a different one from the prose's. Like the wildcard check below and
# UNLIKE the enumeration check above it does not stop the gate: a disagreement cannot make the later
# stages measure the wrong tree, it just must not reach `main` unremarked. The tag half SKIPs out loud on
# a machine that holds only this repository — every gate runner — and the skip is carried in the same
# coverage line so a green here says what was and was not compared.
echo '### SPEC PIN (one revision, five places) ###'
SP_LOG="$LOGDIR/full_spec_pin.log"
bash scripts/spec_pin_check.sh > "$SP_LOG" 2>&1
sp_rc=$?
grep -E "^(spec pin:|\*\*\* spec pin)" "$SP_LOG"
sp_cover="$(grep -E "^spec pin: revision=" "$SP_LOG" | tail -1 | sed 's/^spec pin: //')"
if [ "$sp_rc" != "0" ]; then
  echo "  FAILURES (from $SP_LOG):"; grep -E "^spec pin: FAIL" "$SP_LOG" | head -20 | sed 's/^/    /'
  fail=1
fi
# The same proof-of-work rule as every stage above: agreement with nothing must not read as agreement.
if [ -z "$sp_cover" ]; then
  echo "  (scripts/spec_pin_check.sh printed no 'revision=' coverage line — what it compared is unknown,"
  echo "   treating as a failure)"
  fail=1; sp_cover="UNKNOWN — no coverage line"
fi

# AGENTS.md stays at most 150 lines (#1130): rules there, reasons in docs/rationale/. A text count, cheap,
# and like the pin check it does not stop the gate.
echo '### AGENTS.md SIZE (rules only, at most 150 lines) ###'
if ! bash scripts/agents_size_check.sh; then fail=1; fi

# The WILDCARD-ARM check (issue #658). A pure source scan like the idiom gate — no compiler, ~8 s —
# and it runs here, before the six minutes of building, because the author of a new `_ =>` arm should
# hear about it at the cheapest moment. It holds NO oracle file: it counts the arms over enumerable
# scrutinees in the MERGE BASE and in this tree and refuses an unacknowledged increase, so there is no
# committed number to regenerate and nothing for two lanes to conflict over. Unlike the enumeration
# check above it does not stop the gate: an added wildcard arm does not make the later stages measure
# the wrong tree, it just must not reach `main` unremarked.
echo '### WILDCARD ARMS (a new `_ =>` over an enumerable scrutinee) ###'
WA_LOG="$LOGDIR/full_wildcard_arms.log"
bash scripts/wildcard_arm_check.sh > "$WA_LOG" 2>&1
wa_rc=$?
grep -E "^(wildcard arms|\*\*\* wildcard arms|    )" "$WA_LOG"
wa_cover="$(grep -E "^wildcard arms: base=" "$WA_LOG" | tail -1 | sed 's/^wildcard arms: //')"
if [ "$wa_rc" != 0 ]; then
  echo "  FAILURES (from $WA_LOG):"; grep -E "^wildcard arms: FAIL|^    \+ " "$WA_LOG" | head -20 | sed 's/^/    /'
  fail=1
fi
# A check that printed no counts cannot be told apart from one that scanned nothing — the same
# proof-of-work rule every stage below follows.
if [ -z "$wa_cover" ]; then
  echo "  (scripts/wildcard_arm_check.sh printed no 'base=' coverage line — what it counted is"
  echo "   unknown, treating as a failure)"
  fail=1; wa_cover="UNKNOWN — no coverage line"
fi

# The STRICT-FORMS check, lexical half (issue #691). A pure source scan like the wildcard check above,
# for the same reasons and in the same place: no compiler, ~3 s, no oracle file — it counts the forms
# AGENTS.md "Strict forms" retires in the MERGE BASE and in this tree and refuses an unacknowledged
# increase per rule. It does not stop the gate. The typed half (implicit pointer crossings and null
# sentinels, which need the checker's types) runs after the build, below.
echo '### STRICT FORMS (lexical: unchecked, kind literals, inline `?` values) ###'
SF_LOG="$LOGDIR/full_strict_forms.log"
bash scripts/strict_forms_check.sh > "$SF_LOG" 2>&1
sf_rc=$?
grep -E "^(strict forms|\*\*\* strict forms|    )" "$SF_LOG"
sf_cover="$(grep -E "^strict forms: base=" "$SF_LOG" | tail -1 | sed 's/^strict forms: //')"
if [ "$sf_rc" != 0 ]; then
  echo "  FAILURES (from $SF_LOG):"; grep -E "^strict forms: FAIL|^    \+ " "$SF_LOG" | head -20 | sed 's/^/    /'
  fail=1
fi
if [ -z "$sf_cover" ]; then
  echo "  (scripts/strict_forms_check.sh printed no 'base=' coverage line — what it counted is unknown,"
  echo "   treating as a failure)"
  fail=1; sf_cover="UNKNOWN — no coverage line"
fi

echo "### FIXPOINT ###"
bash scripts/fixpoint.sh > "$FP_LOG" 2>&1
grep -iE "TOOL-1 FIXPOINT|FAIL" "$FP_LOG"
grep -q "TOOL-1 FIXPOINT: seed == Stage1 == Stage2" "$FP_LOG" || { echo "  (fixpoint NOT green — a reseed change needs the 3-stage check; see \"Reproducibility\" in AGENTS.md and docs/rationale/reproducibility.md)"; fail=1; }

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
grep -E "^corpus manifest: (  sha256|detector|re-observation|WARNING|rows=|match|MISMATCH|WROTE)" "$CM_LOG"
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
# `fmt corpus selftest` is surfaced beside the coverage lines for the same reason the sweeps surface
# theirs: it is the non-vacuity check on the two wall-clock ceilings and the ALLOW deciders, and a
# gate that hides whether its own self-test ran cannot be told apart from one that skipped it.
grep -E "^(fmt corpus selftest|fmt corpus walk=|\*\*\* fmt corpus)" "$FC_LOG"
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

# The IDIOM gate. A ratchet: it needs no compiler — a pure source scan, so it can never
# collide with another lane over target/debug/alatyr. It fails only on a duplicate decision that is NOT in
# scripts/idiom.baseline, and it runs its own gate-of-the-gate first (five planted defects that every
# rule must fire on, and a clean twin that none may fire on) — so a green here means the detector was
# alive when it said so.
echo "### IDIOM (duplicate-decision detector: a decision outside scripts/idiom.baseline fails) ###"
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

# The #299 BRAND CENSUS's planted non-vacuity (`scripts/brand_census.sh planted`). The census counts
# brand crossings on file descriptor 99 and is what #544 stage 0's refusals were licensed by, so a
# blind counter is not a harmless one: #679 was a counter that could not fire on any array element,
# and it survived four slices because nothing ran its self-test. `planted` feeds it known crossings,
# which must produce rows of the named class, and legal programs, which must produce none while
# proving by their `sinks=` count that they were visited. It uses the Stage2 compiler the fixpoint
# step leaves at target/debug/alatyr and writes only under target/brand_census.
echo "### BRAND CENSUS (planted: crossings must count, legal programs must not) ###"
BC_LOG="$LOGDIR/full_brand_census.log"
bash scripts/brand_census.sh planted > "$BC_LOG" 2>&1
bc_rc=$?
grep -E "^  planted cases=|^\*\*\* brand census" "$BC_LOG"
if [ "$bc_rc" != 0 ]; then
  echo "  FAILURES (from $BC_LOG):"; grep -E " BAD | BLIND " "$BC_LOG" | head -20 | sed 's/^/    /'
  fail=1
fi
if ! grep -qE "^  planted cases=[0-9]+  failures=0$" "$BC_LOG"; then
  echo "  (scripts/brand_census.sh printed no 'planted cases=N  failures=0' line — what it ran is unknown,"
  echo "   treating as a failure)"
  fail=1
fi

# The #529 PTRINT CENSUS's planted non-vacuity (`scripts/ptrint_census.sh planted`), next to the
# brand census for the same reason. It counts the places where the implicit `usize <-> ptr(T)` seam
# decides a verdict, on file descriptor 98, and #529's slices are licensed by it. Its NEGATIVE fixture
# (explicit `unchecked bitcast` only) went from 0 rows to 6 when the checker began typing a bitcast by
# its operand, and nothing noticed: the census then counted ~350 explicit casts as seam crossings.
# `planted` must fire in both directions on a program built to trip it, put exactly one row inside a
# grant, and give ZERO rows on the explicit twin. Same Stage2 compiler, writes only under
# target/ptrint_census.
echo "### PTRINT CENSUS (planted: seam crossings must count, explicit bitcasts must not) ###"
PC_LOG="$LOGDIR/full_ptrint_census.log"
bash scripts/ptrint_census.sh planted > "$PC_LOG" 2>&1
pc_rc=$?
grep -E "^  planted rows=|^  NEGATIVE fixture|^\*\*\* ptrint census" "$PC_LOG"
if [ "$pc_rc" != 0 ]; then
  echo "  FAILURES (from $PC_LOG): scripts/ptrint_census.sh planted exited $pc_rc"
  fail=1
fi
if ! grep -qE "^  NEGATIVE fixture \(explicit bitcasts only\): check rc=0 rows=0 tag_compat calls=[1-9]" "$PC_LOG"; then
  echo "  (scripts/ptrint_census.sh printed no 'NEGATIVE fixture … rc=0 rows=0 tag_compat calls=N' line —"
  echo "   the explicit twin was not proven clean, treating as a failure)"
  fail=1
fi

# THE CENSUS ITSELF, in the gate (#529 step 3). The stage above proves the counter CAN fire; it pins
# nothing, so no ptrint number was ever in the gate and "OP-CMP = 0" described a run nobody repeated.
# `gate` runs the census over src/, lib/ and every tracked fixture, ratchets `places` and `blind-lib`
# against scripts/ptrint_census.baseline, and prints `op-cmp=UNMEASURED` while the OP-CMP hook is
# unproven — a zero from a hook that has never fired is silence, and this line must not let it read as
# cleanliness. Same Stage2 compiler; writes only under target/ptrint_census. ~5 min at jobs=8.
echo "### PTRINT CENSUS GATE (places and blind-lib ratcheted; unproven classes reported UNMEASURED) ###"
# Prove the ratchet can refuse BEFORE trusting it to hold: a ratchet nobody has seen fail is a ratchet
# that has never been checked, and this stage's whole claim is that growth becomes impossible.
bash scripts/ptrint_census.sh self-test || fail=1
PCG_LOG="$LOGDIR/full_ptrint_gate.log"
bash scripts/ptrint_census.sh gate > "$PCG_LOG" 2>&1
pcg_rc=$?
grep -E "^ptrint census gate:|^ptrint ratchet:|^  op-cmp=UNMEASURED|^  coverage:" "$PCG_LOG"
if [ "$pcg_rc" != 0 ]; then
  echo "  FAILURES (from $PCG_LOG): scripts/ptrint_census.sh gate exited $pcg_rc"
  fail=1
fi
if ! grep -q "^ptrint census gate: places=[0-9]* op-cmp=" "$PCG_LOG"; then
  echo "  (scripts/ptrint_census.sh printed no 'ptrint census gate: places=… op-cmp=…' line —"
  echo "   the census produced no number, treating as a failure)"
  fail=1
fi

# The SEED-FORMS registry (strict_forms.md §8; owner decision on #785). Each form the frozen seed
# miscompiles has a planted program under scripts/seed_forms/ (outside the `test/*.al` corpus), and
# scripts/seed_forms.tsv gives its due exit value. A `seed` row needs the Stage2 compiler the fixpoint
# step left at target/debug/alatyr to answer the due value, and the seed NOT to. So a promotion that
# fixes a form turns this stage red, with the workaround sites to clean up, and the entry retires. A
# `tree` row is a tree defect that a workaround comment blamed on the seed. It must still fail in the
# tree, so the fix that lands for it has to move the row to `seed`.
echo "### SEED FORMS (registry: the seed must still miscompile each form, the tree must not) ###"
SFR_LOG="$LOGDIR/full_seed_forms.log"
SEED_FORMS_TREE="$ROOT/target/debug/alatyr" bash scripts/seed_forms_check.sh > "$SFR_LOG" 2>&1
sfr_rc=$?
grep -E "^(seed forms: rows=|\*\*\* seed forms|seed forms: FAIL)" "$SFR_LOG"
sfr_cover="$(grep -E "^seed forms: rows=" "$SFR_LOG" | tail -1 | sed 's/^seed forms: //')"
if [ "$sfr_rc" != 0 ]; then
  echo "  FAILURES (from $SFR_LOG): scripts/seed_forms_check.sh exited $sfr_rc"
  fail=1
fi
if [ -z "$sfr_cover" ]; then
  echo "  (scripts/seed_forms_check.sh printed no 'rows=' coverage line — what it ran is unknown,"
  echo "   treating as a failure)"
  fail=1; sfr_cover="UNKNOWN — no coverage line"
fi

# The IR VERIFIER stage (`docs/ir.md` §5, `docs/ir-slice-1.md` §5.2). The shared IR's builder runs over
# every function of the tracked test/ corpus, lib/ and src/ (`alatyr ir`), and the verifier runs on
# every function it builds. A refusal is a located internal error, so ANY `VerifyFailed` line, an `ir`
# run's internal-error exit 70, a crash, a timeout or a run with no summary fails the gate. The stage
# proves it can fail before it is believed: `ir_census.sh --self-test` feeds the decision planted report
# directories (a clean one that must pass, one per failure class that must fail by name), and the
# census refuses to count anything until `alatyr ir --self-test` has shown every verifier rule refusing
# its planted violation. Inert: nothing emitted depends on the IR before slice 1c.
echo "### IR VERIFIER (every built function of test/, lib/, src/ must verify; planted refusals must fail) ###"
IRV_LOG="$LOGDIR/full_ir_verify.log"
bash scripts/ir_census.sh --self-test > "$IRV_LOG" 2>&1
irv_st_rc=$?
ALATYR="$ROOT/target/debug/alatyr" bash scripts/ir_census.sh --gate --quiet --jobs "${ALATYR_IR_JOBS:-8}" >> "$IRV_LOG" 2>&1
irv_rc=$?
grep -E "^(ir_census self-test:|ir self-test:|  (set|corpus|lib/|src/) |ir census gate:|\*\*\* ir census gate|ir coverage per backend:|  backend |  (x86_64|aarch64|riscv64|wasm) +[0-9]|ir targets gate:|\*\*\* ir targets)" "$IRV_LOG"
irv_cover="$(grep -E "^ir census gate: " "$IRV_LOG" | tail -1 | sed 's/^ir census gate: //')"
# The per-backend coverage line (`--targets`, implied by --gate): the number that says each of the four
# emitters really lowers from the shared IR, and the one §7.2 needs before it may delete a backend's
# private copies. Absent means the measurement did not happen — unknown, so a failure, by the same rule
# as the verifier's coverage line above.
ir_cov="$(grep -E "^ir coverage per backend:" "$IRV_LOG" | tail -1)"
if [ -z "$ir_cov" ]; then
  echo "  (scripts/ir_census.sh --gate printed no per-backend coverage line — whether the four backends"
  echo "   lower from the shared IR is unknown, treating as a failure)"
  fail=1
fi
if [ "$irv_st_rc" != 0 ] || [ "$irv_rc" != 0 ]; then
  echo "  FAILURES (from $IRV_LOG): census self-test rc=$irv_st_rc, verifier gate rc=$irv_rc"
  grep -E "^(FAIL|  failed corpus runs|    |  VERIFIER REFUSALS)" "$IRV_LOG" | head -20 | sed 's/^/  /'
  fail=1
fi
if [ -z "$irv_cover" ]; then
  echo "  (scripts/ir_census.sh --gate printed no 'ir census gate:' coverage line — what it verified is"
  echo "   unknown, treating as a failure)"
  fail=1; irv_cover="UNKNOWN — no coverage line"
fi

# The SIGNEDNESS CENSUS's record-context self-test (`docs/ir-slice-1.md` §8.5, step e4). The census
# itself only reports, but the record keys it reads are what 1e will switch x86's queries onto, so its
# planted programs run here: a generic instance's operand is unknown with no context and typed in its
# instance; a `comptime for` member's and a pack element's are typed only in their own iteration.
echo "### SIGN CENSUS (self-test, then the corpus ratchet: signedness from sema, not from shape) ###"
SC_LOG="$LOGDIR/full_sign_census_selftest.log"
ALATYR="$ROOT/target/debug/alatyr" bash scripts/sign_census.sh --self-test > "$SC_LOG" 2>&1
sc_rc=$?
grep -E "^(FAIL|sign_census self-test:)" "$SC_LOG"
if [ "$sc_rc" != 0 ] || ! grep -qE "^sign_census self-test: [0-9]+ checks, 0 failed$" "$SC_LOG"; then
  echo "  FAILURES (from $SC_LOG): sign census self-test rc=$sc_rc"
  fail=1
fi
# The corpus run, gated. Until now only the SELF-TEST ran here: the design's second clause — width and
# signedness are attributes of the value, derived ONCE from sema (§3.8) — had a proof that the instrument
# works and no number for the tree. Measured over 2319 programs it is NOT yet true on the twins: x86_64
# disagrees with sema's recorded signedness at 4 of 17587 decisions (its queries were switched onto the
# table), aarch64 at 165 of 448, riscv64 at 156 of 424, wasm at 158 of 435. Each one is a `/ % < > <= >=`
# where the emitter chose signedness from the expression's SHAPE — the #764/#765/#766 family, found by
# the census rather than by a generator's luck. The ratchet holds the line so the family cannot grow while
# the slices close it; the counts are printed, because a held number nobody reads is not a gate.
SCC_LOG="$LOGDIR/full_sign_census.log"
ALATYR="$ROOT/target/debug/alatyr" bash scripts/sign_census.sh --gate --only corpus --list 8 --jobs "${ALATYR_IR_JOBS:-8}" > "$SCC_LOG" 2>&1
scc_rc=$?
grep -E "^(sign census — |  (backend|x86_64|aarch64|riscv64|wasm) |sign census counts |sign census gate:|\*\*\* sign census gate)" "$SCC_LOG"
if [ "$scc_rc" != 0 ]; then
  echo "  FAILURES (from $SCC_LOG): sign census gate rc=$scc_rc"
  grep -E "^(sign ratchet:|\*\*\* sign census gate)" "$SCC_LOG" | head -8 | sed 's/^/  /'
  fail=1
fi
if ! grep -q '^sign census counts corpus:' "$SCC_LOG"; then
  echo "  (the sign census printed no machine-readable counts line — whether the twins agree with sema is"
  echo "   unknown, treating as a failure)"
  fail=1
fi

# The STRICT-FORMS check, typed half (issue #691). `p == 0` with `p : ptr(T)` is invisible to a
# tokenizer, and the checker already names it: the #529 instrument writes each implicit usize<->ptr
# crossing to fd 98. The Stage2 compiler checks the MERGE BASE and this tree (the base from its own
# extraction, with the compiler copied into its target/ so it reads the base lib/) and refuses a new
# implicit crossing, or a new null sentinel counting explicit and implicit forms together. Its planted
# proof runs first: a new `p != 0` must add a row and its explicit twin must not, or the count is blind.
echo "### STRICT FORMS (typed: implicit pointer crossings and null sentinels) ###"
ST_LOG="$LOGDIR/full_strict_typed.log"
bash scripts/strict_forms_check.sh --typed-self-test > "$ST_LOG" 2>&1
st_st_rc=$?
bash scripts/strict_forms_check.sh --typed >> "$ST_LOG" 2>&1
st_rc=$?
grep -E "^(strict forms typed|\*\*\* strict forms typed|strict forms: FAIL|    \+ )" "$ST_LOG"
st_cover="$(grep -E "^strict forms typed: base=" "$ST_LOG" | tail -1 | sed 's/^strict forms typed: //')"
if [ "$st_st_rc" != 0 ] || [ "$st_rc" != 0 ]; then
  echo "  FAILURES (from $ST_LOG): typed self-test rc=$st_st_rc, typed check rc=$st_rc"
  fail=1
fi
if [ -z "$st_cover" ]; then
  echo "  (scripts/strict_forms_check.sh --typed printed no 'base=' coverage line — treating as a failure)"
  fail=1; st_cover="UNKNOWN — no coverage line"
fi

# The CROSS-BACKEND ratchet (#683). It needs no compiler: it is a join over scripts/corpus.manifest,
# which the CORPUS stage above has already checked against the tree on this same run.
#
# There used to be a second, REPORTING-ONLY stage here, `scripts/xbackend_report.sh`, which asked
# one narrower question of the same rows (does a twin exit normally with a different, quiet answer?)
# and exited 0 whatever it found. #1128 removed it: nothing in this script prints a finding and
# passes. Measured: a planted quiet wrong value (riscv64 41 where x86_64 runs 42, on
# test/accept_limit_no_unchecked_neg.al) made the report print the row and exit 0, while
# `xbackend_diff.sh --ratchet` failed with "UNEXPLAINED quiet disagreements GREW 0 -> 1". The one
# row shape only the report used to show was a quiet answer on a HW-DEFINED or RAW-ESCAPE path,
# which leaves every other count; the ratchet now holds `hw-defined=` and `raw-escape=` on their own
# (a wasm `unchecked_div_zero` trap turned quiet 7: report exit 0, old ratchet exit 0, now FAIL 8 -> 9).
echo "### CROSS-BACKEND (xbackend_diff: RATCHET, growth gates) ###"
XB_LOG="$LOGDIR/full_xbackend.log"
: > "$XB_LOG"
## The WIDER question (#683): every (phase, exit) disagreement between x86_64 and a
## twin, classified — traps, crashes, build-step failures and twins accepting what x86_64 refuses, not
## only quiet wrong values. `--ratchet`, NOT `--count`: the count used to be reporting-only
## (`--count` ended in `exit 0` whatever it printed), so a PR that ADDED a disagreement passed and the
## only trace was a number in a log nobody read — that is how `paths` reached 950. The ratchet holds
## the line without pretending the backlog is empty: the count may not GROW, and it never demands zero
## (the 833 TRAP paths are unimplemented lowerings, IR slices 3–8, not defects this change introduced).
## Growing the count, or a missing/malformed baseline, sets `fail`; so does a broken self-test or a
## missing proof line. Lowering the count passes and says to tighten the baseline in the same PR.
bash scripts/xbackend_diff.sh --self-test >> "$XB_LOG" 2>&1
xd_st_rc=$?
bash scripts/xbackend_diff.sh --ratchet >> "$XB_LOG" 2>&1
xd_rc=$?
grep -E "^(xbackend_diff self-test:|xbackend diff:|xbackend ratchet:)" "$XB_LOG"
if [ "$xd_st_rc" != 0 ] || [ "$xd_rc" != 0 ] || [ "$(grep -cE '^xbackend diff: paths=' "$XB_LOG")" != 1 ]; then
  echo "  scripts/xbackend_diff.sh failed its self-test or its RATCHET (the disagreement count grew"
  echo "  past scripts/xbackend_diff.baseline, or the baseline is missing/malformed), or printed no"
  echo "  'xbackend diff: paths=' proof-of-work line (from $XB_LOG):"
  grep -E "^  FAIL |^xbackend ratchet:" "$XB_LOG" | head -8 | sed 's/^/    /'
  fail=1
fi

# The x86 DIFFERENTIAL of the shared IR (`docs/ir.md` §7.1 rule 5, IR slice 1d). Every corpus program
# with a function the IR builds and `src/lower/isel.al` selects is built and run through the default x86
# path and through the `alatyr x86-ir` dev verb, and the two exits and stdouts are compared. Each
# disagreement is a triage item (an IR bug, or a legacy x86 bug the IR answers per the specification —
# #872's narrowing, the signedness family), so a single row does not set `fail`; the COUNT of them is
# ratcheted below by scripts/ir_diff.baseline, and growth does. A broken self-test, an unreadable run, or a proof line that walked no
# program with a selected function does: "found nothing" must be told apart from "compared nothing".
echo "### IR DIFF (x86 vs x86-via-IR: the disagree count is RATCHETED by scripts/ir_diff.baseline) ###"
IRD_LOG="$LOGDIR/full_ir_diff.log"
bash scripts/ir_diff.sh --self-test > "$IRD_LOG" 2>&1
ird_st_rc=$?
ALATYR="$ROOT/target/debug/alatyr" bash scripts/ir_diff.sh --quiet --jobs "${ALATYR_IR_JOBS:-8}" >> "$IRD_LOG" 2>&1
ird_rc=$?
grep -E "^(ir_diff self-test:|ir diff:|  DISAGREE |  VERIFIER REFUSALS|    test/)" "$IRD_LOG"
ird_cover="$(grep -E "^ir diff: " "$IRD_LOG" | tail -1 | sed 's/^ir diff: //')"
ird_withir="$(sed -nE 's/^ir diff: programs=[0-9]+ with-ir=([0-9]+) .*/\1/p' "$IRD_LOG" | tail -1)"
if [ "$ird_st_rc" != 0 ] || [ "$ird_rc" != 0 ] || [ -z "$ird_withir" ] || [ "$ird_withir" = 0 ]; then
  echo "  scripts/ir_diff.sh failed its self-test, could not take the differential, or printed no"
  echo "  'ir diff:' line with a program compared (from $IRD_LOG):"
  grep -E "^(FAIL |ir_diff: )" "$IRD_LOG" | head -5 | sed 's/^/    /'
  fail=1
fi

# The COPY LIFT gate (criterion 2, "the emitters' private copies go away"). `scripts/copy_lift.py`
# answers which duplicated decisions can be deleted TODAY — identical x3, no backend global, and no
# backend-local callee anywhere in the transitive closure. It holds that count at zero, so "can be
# deleted and was not" becomes a gate failure rather than a note in a doc; the blocked families are
# printed with their blockers, which is the queue for the next slice. Proven to refuse before trusted:
# a planted identical triple makes it exit 1, a missing baseline exits 2.
python3 scripts/copy_lift.py --self-test || fail=1
CL_LOG="$LOGDIR/full_copy_lift.log"
python3 scripts/copy_lift.py --gate > "$CL_LOG" 2>&1
cl_rc=$?
grep -E "^copy lift gate:|^  LIFTABLE " "$CL_LOG"
if [ "$cl_rc" = 1 ]; then
  echo "  FAILURES (from $CL_LOG): a family of private copies can be deleted and is still in the tree"
  fail=1
elif [ "$cl_rc" != 0 ]; then
  echo "  FAILURES (from $CL_LOG): the copy-lift gate could not judge (exit $cl_rc) — an unheld count is not a pass"
  fail=1
fi

# "reporting only" is how five disagreements between the two x86 paths stayed invisible for a cycle:
# the numbers were printed, the gate was green, and nothing named them. The findings stay non-gating
# as a differential (a wrong value is xbackend_diff's to gate), but the COUNT of programs where the
# two paths disagree is now held, so it cannot grow and every row still in it stays named here.
IRD_BASE="$ROOT/scripts/ir_diff.baseline"
ird_now="$(sed -nE 's/^ir diff: .*disagree=([0-9]+) .*/\1/p' "$IRD_LOG" | tail -1)"
if [ -z "$ird_now" ]; then
  echo "  ir_diff printed no disagree= count to hold: the differential did not complete."
  fail=1
elif [ ! -f "$IRD_BASE" ]; then
  echo "  no scripts/ir_diff.baseline: the disagree count is unheld. Record it with"
  echo "    bash scripts/ir_diff.sh --quiet --jobs ${ALATYR_IR_JOBS:-8} | sed -nE 's/^ir diff: .*disagree=([0-9]+) .*/\1/p' | tail -1 > scripts/ir_diff.baseline"
  echo "  after naming each program the count covers, or set it by hand to what is explained."
  fail=1
else
  # only the first line is the number: the file's prose is full of corpus counts, and taking every
  # digit in it would build a baseline no regression could ever exceed.
  ird_base="$(head -1 "$IRD_BASE" | tr -dc '0-9')"
  if [ -z "$ird_base" ]; then
    echo "  scripts/ir_diff.baseline holds no number."
    fail=1
  elif [ "$ird_now" -gt "$ird_base" ]; then
    echo "  IR DIFF REGRESSION: disagree=$ird_now, baseline $ird_base. The two x86 paths diverge on"
    echo "  more programs than the recorded, explained set; each new row is a defect in the shared IR"
    echo "  path or in the emitter, and neither is fixed by raising the baseline."
    grep -E "^  DISAGREE " "$IRD_LOG" | head -10 | sed 's/^/    /'
    fail=1
  else
    echo "  disagree=$ird_now held at or below baseline $ird_base; the rows it covers:"
    grep -E "^  DISAGREE " "$IRD_LOG" | sed 's/^/    /'
  fi
fi

echo "### SWEEPS (conditional) ###"
bash scripts/sweeps.sh "${SWEEP_ARGS[@]}" 2>&1 | tee "$LOGDIR/full_sweeps.log"
[ "${PIPESTATUS[0]}" = 0 ] || fail=1
sw_status="$(grep -oE '^sweeps: STATUS=[A-Z]+' "$LOGDIR/full_sweeps.log" | tail -1 | cut -d= -f2)"
if [ -z "$sw_status" ]; then
  echo "  (scripts/sweeps.sh printed no STATUS line — the sweep outcome is unknown, treating as a failure)"
  fail=1; sw_status=UNKNOWN
fi

# The SEEDED PROGRAM GENERATOR (#582), now IN THE GATE. Criterion 4 is "no wrong value, no crash, on
# any backend", and until now that sentence was held by nobody: `progen.py` existed and was run by
# hand, so "progen green" meant somebody remembered to run it. Every fixture under test/ is one point
# someone thought to write; progen generates programs valid BY CONSTRUCTION and runs each on all four
# backends, so a disagreement needs no expected value to be found — which is exactly the class of bug
# the fixtures structurally miss, and why it belongs beside the sweeps rather than in a nightly nobody
# reads.
#
# The seed range is FIXED so the gate is reproducible: the same tree answers the same way twice, and a
# seed that once failed keeps failing until it is fixed. `ALATYR_PROGEN_SEEDS` widens the count for a
# nightly without changing what the pinned range means. The self-test runs first, by the house rule
# that a check must prove it can fail before it is believed.
#
# `progen.py run` exits non-zero on WRONG, REFUSED or CRASH — and REFUSED is included because a
# program valid by construction that the compiler refuses IS a defect, so this stage is stricter than
# the criterion it holds. It does NOT exit non-zero on HANG, so the summary is read here too: a
# backend that hangs is not a green night either. No summary line means nothing ran — unknown, so a
# failure, by the same rule as every other coverage line in this script.
echo "### PROGEN (seeded generator: one program, four backends, no expected value needed) ###"
PG_LOG="$LOGDIR/full_progen.log"
python3 scripts/progen.py self-test > "$PG_LOG" 2>&1
pg_st_rc=$?
grep -E "^progen self-test:" "$PG_LOG" | tail -1 | sed 's/^/  /'
if [ "$pg_st_rc" != 0 ]; then
  echo "  FAIL progen self-test: rc=$pg_st_rc — the generator's own differential is not proven, so"
  echo "   a green run below would mean nothing"
  fail=1
fi
# No silent fallback to a compiler that is not there: if the binary is missing, every generated
# program "refuses" for the same reason and the counts would still read clean.
if [ ! -x "$ROOT/target/debug/alatyr" ]; then
  echo "  FAIL progen: no executable at $ROOT/target/debug/alatyr — the stage would report a green"
  echo "   built on nothing, so it refuses to run at all"
  fail=1; pg_cover="NOT RUN — no compiler"
fi
pg_seeds="${ALATYR_PROGEN_SEEDS:-300}"
pg_start="${ALATYR_PROGEN_START:-1}"
if [ "$pg_seeds" -lt 1 ] 2>/dev/null; then
  echo "  FAIL progen: ALATYR_PROGEN_SEEDS=$pg_seeds generates no program at all — a run that"
  echo "   compares nothing is not a green night, whatever it prints"
  fail=1
fi
python3 scripts/progen.py run --seed "$pg_start" --count "$pg_seeds" \
  --jobs "${ALATYR_PROGEN_JOBS:-4}" --cc "$ROOT/target/debug/alatyr" >> "$PG_LOG" 2>&1
pg_rc=$?
pg_line="$(grep -E '^progen: seeds=' "$PG_LOG" | tail -1)"
pg_hang="$(printf '%s' "$pg_line" | grep -oE 'hang=[0-9]+' | cut -d= -f2)"
if [ -z "$pg_line" ]; then
  echo "  (progen printed no summary line — whether any program ran is unknown, treating as a failure)"
  fail=1; pg_cover="UNKNOWN — no progen summary"
else
  echo "  $pg_line"
  grep -E '^progen coverage:' "$PG_LOG" | tail -1 | sed 's/^/  /'
  # `progen.py` fails on compared==0 only when attempted>0; a count of 0 slips past its own rule,
  # so the compared count is checked here too — zero cross-backend comparisons prove nothing.
  pg_cmp="$(grep -E '^progen coverage:' "$PG_LOG" | tail -1 | grep -oE 'compared=[0-9]+' | cut -d= -f2)"
  [ "${pg_cmp:-0}" != 0 ] || { echo "  FAIL progen: compared=0 — no program was compared across two backends"; fail=1; }
  [ "${pg_hang:-0}" != 0 ] && { echo "  FAIL progen: hang=$pg_hang — a backend that never answered is not green"; fail=1; }
  pg_cover="$(printf '%s' "$pg_line" | sed 's/^progen: //;s/ out=.*//')"
fi
if [ "$pg_rc" != 0 ]; then
  echo "  FAIL progen: rc=$pg_rc (WRONG, REFUSED or CRASH; artifacts and a reproduce: command are named in $PG_LOG)"
  grep -E '^(WRONG|CRASH|REFUSED|TIMEOUT|progen: NO program)' "$PG_LOG" | head -12 | sed 's/^/    /'
  fail=1
fi
# The REGRESSION LIST (#1128): every past progen finding that was fixed, replayed with its own forms, so
# a fixed finding cannot return unseen. Each row must produce exactly one agreeing program; a malformed
# row, a run with no summary, or a replayed count short of the row count is a failure, not a skip.
PGR_LIST="$ROOT/scripts/progen_regress.tsv"
PGR_LOG="$LOGDIR/full_progen_regress.log"
: > "$PGR_LOG"
pgr_rows=0; pgr_ok=0
if [ ! -f "$PGR_LIST" ]; then
  echo "  FAIL progen regress: no $PGR_LIST — the replay of past findings is unheld"; fail=1
else
  # `|| [ -n … ]` keeps a last row that has no trailing newline (read fails on it, but has filled it).
  while IFS=$'\t' read -r pgr_seed pgr_forms pgr_issue pgr_rest || [ -n "$pgr_seed" ]; do
    case "$pgr_seed" in ''|'#'*) continue ;; esac
    pgr_rows=$((pgr_rows + 1))
    if ! [[ "$pgr_seed" =~ ^[0-9]+$ ]] || [ -z "$pgr_forms" ] || ! [[ "$pgr_issue" =~ ^#[0-9]+$ ]] || [ -n "$pgr_rest" ]; then
      echo "  FAIL progen regress: malformed row (want seed<TAB>forms<TAB>#issue): $pgr_seed $pgr_forms $pgr_issue $pgr_rest"
      fail=1; continue
    fi
    pgr_fa=(); [ "$pgr_forms" = all ] || pgr_fa=(--forms "$pgr_forms")
    pgr_out="$(python3 scripts/progen.py run --seed "$pgr_seed" --count 1 "${pgr_fa[@]}" \
      --cc "$ROOT/target/debug/alatyr" --out "$ROOT/target/progen_regress" 2>&1 < /dev/null)"
    pgr_rc=$?
    printf '%s\n' "$pgr_out" >> "$PGR_LOG"
    if [ "$pgr_rc" = 0 ] && printf '%s\n' "$pgr_out" | grep -qE '^progen: seeds=.* agree=1 .*hang=0 '; then
      pgr_ok=$((pgr_ok + 1))
    else
      echo "  FAIL progen regress: seed $pgr_seed ($pgr_forms, $pgr_issue) no longer agrees (rc=$pgr_rc):"
      printf '%s\n' "$pgr_out" | grep -E '^(WRONG|CRASH|REFUSED|HANG|MODEL|progen: )' | head -3 | sed 's/^/    /'
      fail=1
    fi
  done < "$PGR_LIST"
  echo "  progen regress: replayed=$pgr_ok/$pgr_rows rows of scripts/progen_regress.tsv"
  [ "$pgr_rows" -gt 0 ] || { echo "  FAIL progen regress: the list holds no row"; fail=1; }
fi

if [ "$fail" != 0 ]; then
  echo "*** FULL GATE: FAILURES ***"
elif [ "$sw_status" = "RAN" ]; then
  echo "*** FULL GATE: GREEN (sweeps RAN) ***"
  echo "    corpus enum:     $ce_cover"
  echo "    spec pin:        $sp_cover"
  echo "    wildcard arms:   $wa_cover"
  echo "    strict forms:    $sf_cover"
  echo "    strict typed:    $st_cover"
  echo "    seed forms:      $sfr_cover"
  echo "    ir verifier:     $irv_cover"
  echo "    ir diff:         ${ird_cover:-NO COVERAGE LINE} (count ratcheted)"
  echo "    corpus manifest: $cm_cover"
  echo "    fmt arbiter:     ${fc_line:-NO COVERAGE LINE}"
  echo "    idiom gate:      ${ig_line:-NO COVERAGE LINE}"
  echo "    progen:          ${pg_cover:-NO SUMMARY LINE}"
else
  echo "*** FULL GATE: GREEN — but the SWEEPS DID NOT RUN (sweeps STATUS=$sw_status): the aarch64/"
  echo "    riscv64/wasm backends were NOT exercised by the sweeps. Re-run with --force-sweeps before"
  echo "    landing any change that can reach a backend. ***"
  echo "    corpus enum:     $ce_cover"
  echo "    spec pin:        $sp_cover"
  echo "    wildcard arms:   $wa_cover"
  echo "    strict forms:    $sf_cover"
  echo "    strict typed:    $st_cover"
  echo "    seed forms:      $sfr_cover"
  echo "    ir verifier:     $irv_cover"
  echo "    ir diff:         ${ird_cover:-NO COVERAGE LINE} (count ratcheted)"
  echo "    corpus manifest: $cm_cover"
  echo "    fmt arbiter:     ${fc_line:-NO COVERAGE LINE}"
  echo "    idiom gate:      ${ig_line:-NO COVERAGE LINE}"
  echo "    progen:          ${pg_cover:-NO SUMMARY LINE}"
fi
exit "$fail"
