#!/usr/bin/env bash
# scripts/sweeps.sh — run the a64/rv64/wasm sweeps CONDITIONALLY, and say exactly what it decided.
#
# The three sweeps (qemu-run of the corpus on aarch64/riscv64 + wasmtime) used to be the slow part of
# the gate (measured 4 m 10 s). Each is ~640 INDEPENDENT emit+assemble+link+emulate chains, so each
# sweep now runs its corpus on `$(nproc)` workers (`ALATYR_JOBS=<n>`; 1 = strict corpus order, for
# reproducing a confusing failure in sequence). The parallelism is INSIDE each sweep, where the
# independent work is; the three still run one after another so the per-backend
# `match/trap/reject` reports stay in a fixed order and one backend's failure output cannot be
# interleaved with another's. See `sweep_run_corpus` and `sweep_selftest` in scripts/sweep_common.sh —
# the latter is the gate of the gate for the parallel driver and runs before every sweep.
#
# They only need to run when a change can affect NON-x86 output. A change confined to the
# x86 code-emit files below provably cannot change what aarch64.al/riscv64.al/wat.al produce, so the
# sweeps are SKIPPED (correctly, not just for speed). Any other sweep-relevant change — front-end
# (parser/sema/ast/comptime/lexrt/lower_layout), the non-x86 backends, the runtime, the driver, `lib/`,
# the manifest, or the e2e table that IS the sweep corpus — runs them.
#
# ## Why the skip decision is now spelled out
#
# This script used to compare against `HEAD` by default. `git diff HEAD` sees only UNCOMMITTED work, so
# the moment a lane committed its change — or an integrator cherry-picked one onto `main` — the very
# change the gate exists to police became invisible and the script printed
#     sweeps: SKIPPED (no src/*.al change → no codegen change).
# on a tree whose backend files had just changed. A false FAIL is annoying; a false SKIP is a hole in
# the authoritative gate, because `full.sh` then reports GREEN having exercised no backend at all.
# (The old `^src/.*\.al$` filter also never matched `lib/`, though its own header promised it would.)
#
# The rules now are:
#   • the base is RESOLVED EXPLICITLY and PRINTED, so a reader can judge whether the answer means anything;
#   • an implicit base is `git merge-base HEAD <integration ref>` (default `main`) — that sees a lane's
#     COMMITTED work, which is the case that broke;
#   • if no meaningful base exists (HEAD is contained in the integration ref — e.g. an integrator on
#     `main`, where committed work is indistinguishable from the branch itself), the sweeps RUN. Fail
#     safe: never skip on an answer we cannot trust. Pass an explicit base ref to opt into a fast skip.
#   • a SKIP is announced as "NOT RUN … the backends were NOT exercised", never as a pass.
#
# ## Usage (inside `nix develop`)
#   bash scripts/sweeps.sh [--force] [<base-ref>]
#     --force      run the sweeps regardless of the diff
#     <base-ref>   compare against this ref explicitly (+ working tree + untracked)
#   SWEEPS_INTEGRATION_REF=<ref>   override the implicit base's integration ref (default `main`)
#   ALATYR_JOBS=<n>                workers inside each sweep (default `nproc`; 1 = serial)
#
# ## Output contract
#   `sweeps: STATUS=RAN|SKIPPED|REGRESSION` — one machine-readable line, always printed.
#   Exit 0 = ran clean OR skipped; 1 = a sweep regressed. (Unchanged, so `full.sh || fail=1` still
#   holds; `full.sh` additionally reads the STATUS line so a SKIP cannot read as a pass.)
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT" || exit 1
. "$ROOT/scripts/sweep_common.sh"

FORCE=0
if [ "${1:-}" = "--force" ]; then FORCE=1; shift; fi
BASE_ARG="${1:-}"
INTEGRATION_REF="${SWEEPS_INTEGRATION_REF:-main}"

# x86-emit-only files: a change confined to these cannot alter non-x86 codegen.
X86_ONLY="src/lower.al src/regalloc.al src/lower_asm.al"
# Everything whose change CAN alter what the sweeps observe: the compiler, the shipped stdlib, the
# manifest, and scripts/e2e.sh — which is not merely a test runner, it is the sweep CORPUS.
RELEVANT_RE='^(src/.*\.al|lib/.*\.al|package\.al|scripts/e2e\.sh)$'

## Resolve the base. Sets `base_sha`, `base_desc`, and `base_ok` (0 = no trustworthy base).
resolve_base() {
  base_sha=""; base_desc=""; base_ok=0
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    base_desc="not a git work tree"
    return 0
  fi
  if [ -n "$BASE_ARG" ]; then
    if ! base_sha="$(git rev-parse --verify --quiet "${BASE_ARG}^{commit}")"; then
      base_desc="explicit base ref '$BASE_ARG' does not resolve"
      return 0
    fi
    base_desc="explicit base ref '$BASE_ARG' = $(git rev-parse --short "$base_sha")"
    base_ok=1
    return 0
  fi
  if ! git rev-parse --verify --quiet "${INTEGRATION_REF}^{commit}" >/dev/null; then
    base_desc="integration ref '$INTEGRATION_REF' does not exist"
    return 0
  fi
  if ! base_sha="$(git merge-base HEAD "$INTEGRATION_REF" 2>/dev/null)"; then
    base_desc="HEAD has no merge base with '$INTEGRATION_REF'"
    return 0
  fi
  if [ "$base_sha" = "$(git rev-parse HEAD)" ]; then
    base_desc="HEAD is contained in '$INTEGRATION_REF' — committed work here is indistinguishable from the branch itself"
    base_sha=""
    return 0
  fi
  base_desc="merge-base with '$INTEGRATION_REF' = $(git rev-parse --short "$base_sha")"
  base_ok=1
  return 0
}

## Everything sweep-relevant that differs from the base: committed (base..HEAD), staged, unstaged and
## untracked — `git diff <base>` already spans commits AND the working tree.
changed_paths() {
  { git diff --name-only "$base_sha" 2>/dev/null
    git ls-files --others --exclude-standard 2>/dev/null
  } | grep -E "$RELEVANT_RE" | sort -u
}

run=1
reason=""
resolve_base
if [ "$FORCE" = 1 ]; then
  echo "sweeps: base=n/a (--force)"
  reason="--force"
elif [ "$base_ok" = 0 ]; then
  echo "sweeps: base=UNDETERMINED ($base_desc)"
  reason="no trustworthy base to diff against — running rather than guessing (pass an explicit base ref for a fast skip)"
else
  echo "sweeps: base=$base_desc"
  changed="$(changed_paths)"
  if [ -z "$changed" ]; then
    echo "sweeps: changed (sweep-relevant): none"
    run=0
    reason="no sweep-relevant change vs $base_desc"
  else
    echo "sweeps: changed (sweep-relevant): $(printf '%s' "$changed" | tr '\n' ' ')"
    only_x86=1
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      hit=0; for w in $X86_ONLY; do [ "$f" = "$w" ] && hit=1; done
      [ "$hit" = 0 ] && only_x86=0
    done <<< "$changed"
    if [ "$only_x86" = 1 ]; then
      run=0
      reason="x86-emit-only change vs $base_desc: $(printf '%s' "$changed" | tr '\n' ' ')"
    else
      reason="sweep-relevant change vs $base_desc"
    fi
  fi
fi

if [ "$run" = 0 ]; then
  echo "sweeps: STATUS=SKIPPED"
  echo "*** sweeps: NOT RUN ($reason). The aarch64/riscv64/wasm backends were NOT exercised. Use --force to run. ***"
  exit 0
fi
echo "sweeps: RUNNING ($reason)"

## Build the compiler under test ONCE and hand the SAME binary to all three sweeps via
## `ALATYR_SWEEP_CC`. Each sweep used to rebuild `target/debug/alatyr` from the seed itself, so one gate run
## did that same build three times, each on top of the previous sweep's artifacts. The state the three
## sweeps share is now explicit, built once, and verified once — here, where a failure can be reported
## properly instead of surfacing as a bare `FAIL: seed build` from whichever sweep hit it.
if ! sweep_build_compiler "$ROOT" sweeps; then
  echo "sweeps: STATUS=REGRESSION"
  echo "*** sweeps: REGRESSION (could not build the compiler under test — see the diagnosis above) ***"
  exit 1
fi
if ! sweep_select_compiler "$ROOT"; then
  echo "sweeps: STATUS=REGRESSION"
  echo "*** sweeps: REGRESSION (seed created no usable compiler-under-test) ***"
  exit 1
fi
export ALATYR_SWEEP_CC="$SWEEP_CC"
echo "sweeps: compiler under test = $ALATYR_SWEEP_CC ($(wc -c < "$ALATYR_SWEEP_CC") bytes)"

fail=0
failed=""
run_sweep() {
  script="$1"; tag="$2"
  out="$(bash "$script" 2>&1 < /dev/null)"; rc=$?
  ## The individual sweep owns the environment contract: a missing optional
  ## cross-toolchain is a successful skip, while an executed sweep must report
  ## that it found no silent miscompiles. Do not turn the former into a gate
  ## regression merely because the wrapper only inspected the last line.
  if printf '%s\n' "$out" | grep -q "no silent miscompiles"; then
    printf '%s\n' "$out" | grep -E "^${tag}_sweep: (compiler|selftest|match)"
    printf '%s\n' "$out" | tail -1
    return 0
  fi
  if printf '%s\n' "$out" | grep -qE '^skip .* (absent)$'; then
    printf '%s\n' "$out" | tail -1
    return 0
  fi
  ## A genuine failure: print EVERYTHING the sweep said. The old wrapper printed the last two lines and
  ## discarded the rest, which is how `rv64_sweep: FAIL: seed build` became the entire public record of
  ## a failure whose real cause sat several lines above it.
  echo "--- ${tag}_sweep FAILED (exit $rc) — full output follows ---"
  printf '%s\n' "$out"
  echo "--- end of ${tag}_sweep output ---"
  return 1
}
echo "=== a64_sweep ===";  run_sweep scripts/a64_sweep.sh  a64  || { fail=1; failed="$failed a64"; }
echo "=== rv64_sweep ==="; run_sweep scripts/rv64_sweep.sh rv64 || { fail=1; failed="$failed rv64"; }
echo "=== wasm_sweep ==="; run_sweep scripts/wasm_sweep.sh wasm || { fail=1; failed="$failed wasm"; }

if [ "$fail" = 0 ]; then
  echo "sweeps: STATUS=RAN"
  echo "*** sweeps: all clean (no silent miscompiles) ***"
else
  echo "sweeps: STATUS=REGRESSION"
  echo "*** sweeps: REGRESSION (failed:$failed) ***"
fi
exit "$fail"
