#!/usr/bin/env bash
# scripts/corpus_manifest.sh — the per-file four-backend behaviour manifest.
#
# ## What it observes
#
# The fixpoint and a tree-level `cmp` of the emitted GAS only exercise the shapes present in the
# compiler's own source tree; the e2e table is smaller still, and the three sweeps only walk its `run`
# rows. This gate runs EVERY tracked `test/*.al` through the x86_64, AArch64, RISC-V64 and WAT paths and
# records, per (source × backend) pair, the terminal phase, its exit status, and the sha256 of the bytes
# it wrote to stdout and stderr. A compile/assemble/link diagnostic is a terminal result too, so a
# `reject_*` fixture keeps a meaningful row without pretending a failed build produced a program.
#
#   row := backend <TAB> path <TAB> phase <TAB> exit <TAB> sha256(stdout) <TAB> sha256(stderr)
#   phase ∈ compile | assemble | link | run  (+ `_timeout` on any of the build phases)
#
# ## Why the rows are reproducible in a DIFFERENT directory
#
# The first cut of this gate hashed stderr that contained ABSOLUTE artifact paths — `ld.bfd:
# <checkout>/target/…/000001.o: in function 'main':`, `wasmtime: failed to run main module
# '<checkout>/…/000000.wasm'` — so 1 641 of 5 636 rows changed the moment the same commit was
# checked out somewhere else, and 617 more carried a `/nix/store/<hash>-…` tool path. A same-directory
# double run cannot see either. Three measures, in order of strength:
#
#   1. every artifact path handed to a tool is RELATIVE to this checkout's root, so no tool diagnostic
#      can name the checkout. That also fixes the second failure class: `argv[0]` of a corpus program is
#      now a CONSTANT-LENGTH relative path, and the initial stack layout (hence what a program reading
#      uninitialized memory sees) no longer depends on how long the checkout's path happens to be;
#   2. every corpus program runs under a FIXED, minimal environment (`env -i` + four constants), so the
#      guest stack does not carry the host's environment either;
#   3. captured stdout/stderr are normalized before hashing — the 32-char `/nix/store` hash, this
#      checkout's path and `$HOME` collapse to fixed tokens, and so does the per-pair artifact prefix,
#      which carries the source's INDEX in the corpus and would otherwise move every row below an added
#      or deleted fixture (measured: 3 242 unrelated rows).
#
# The acceptance test for all of that is NOT a double run in one directory: it is generating the manifest
# in two worktrees whose paths have DIFFERENT LENGTHS and requiring byte-identical files.
#
# ## The gate of the gate (every invocation, cost ~0)
#
# An oracle nobody has seen fail is decoration, so each run proves itself before it is believed:
#   • non-vacuity — rows are counted from the generated BODY (never from the loop counter) and must equal
#     4 × sources − excluded pairs; every source must have produced its own rows; each backend must have
#     reached phase `run` at least once; and each backend's `run` rows must hold at least TWO distinct
#     exit codes, because a runner that answers the same thing for every program is not observing any
#     of them. Both halves were earned: a shimmed always-failing `aarch64-as` let `--write` bless a
#     baseline with ZERO aarch64 `run` rows and exit 0, and an unwritable wasmtime cache directory made
#     all 1 235 wasm `run` rows a uniform `exit 1` that the first assertion alone waved through;
#   • detector self-test — one row's exit field is flipped in a copy of the baseline and the comparison
#     must report exactly that one differing row, which is what proves the compare path is live and the
#     baseline is neither empty nor silently absent;
#   • re-observation self-test — the serial re-observation of a timed-out source (see `reobserve_timeouts`)
#     is driven in BOTH directions with a stubbed worker: a child that times out again must stay a
#     reported failure, and a child that comes back inside the ceiling must return to its observed phase.
#     A mechanism that only ever un-fails rows is not a re-measurement, it is an eraser;
#   • body-shape self-test — the row-count and non-vacuity decision above is itself planted against
#     (`check_body_shape`, issue #600): a truncated body, an overlong one, rows that hold the right
#     LINE count but are not rows, a backend that ran nothing, a runner answering the same thing for
#     every program, and the two bodies it must accept. Until that existed nothing drove the
#     decision, and neutering it let `--write` bless a 400-row oracle for a 2052-source corpus;
#   • provenance — the compiler under test is named with its sha256, a `target/debug/alatyr` older than the
#     newest `src/`/`lib/` file is refused, and a compiler supplied via `ALATYR_CORPUS_CC` that differs
#     from this checkout's own is refused unless the caller says so out loud;
#   • a missing cross tool is exit 2, never a partial green.
#
# ## A `*_timeout` row is re-observed, never guessed (issue #537)
#
# `rc == 124 after N seconds` cannot tell a LOOPING compiler from a starved one, and the walk used to
# fold the answer it did not have into `NO-LONGER-RUNS — a REGRESSION` while printing, in the same run,
# a warning that a timeout row is the one kind it cannot call reproducible. No value of TIMEOUT_SECS
# fixes that: wall-clock time on a shared machine has no upper bound, so a ceiling only sets the load at
# which the false red returns (it was raised from 10 s to 30 s once already, and came back at load 28,
# 33 and 42 on 12 cores). The fine fact is cheap and was never asked — *does this child still fail to
# finish when nothing else of ours is running?* — so every source that produced a `*_timeout` row is
# observed again, ONE AT A TIME, after the parallel walk has finished, and the SECOND observation is the
# one that is classified. A row that breaches the ceiling twice, the second time alone, is reported as
# its own `TIMED-OUT` class instead of a regression class it does not belong to.
#
# ## Usage
#
#   scripts/corpus_manifest.sh [--check|--write|--self-test]
#     --check (default)  regenerate and compare byte-for-byte with scripts/corpus.manifest, which since
#                        #1126 S3 holds the sources with no `## expect:` directive and the directive
#                        sources that print ("the oracle's scope" below); the whole walk is left at
#                        target/corpus-manifest/observed.manifest for fixture_expect.sh --gate
#     --write            overwrite scripts/corpus.manifest (an intentional behaviour change owns this)
#     --explain A B      read two manifests JOINED on (backend, path), grouped by severity class.
#                        A regeneration's commit message carries this output verbatim.
#     --self-test        run the detector, classifier, normalization, stream-separation, re-observation,
#                        body-shape, predicted-delta and frame-layout self-tests only; never walk the
#                        corpus or write scripts/corpus.manifest
#
#   The predicted delta (an intentional behaviour change gated ONCE — see "THE PREDICTED DELTA" below).
#   These four need no compiler, no cross tool and no `nix develop`:
#     --emit-expected COMMITTED FRESH      print the delta that takes COMMITTED to FRESH, in --explain's
#                        classes; a PR author redirects it into scripts/corpus.expected-delta
#     --check-delta COMMITTED FRESH DELTA  0 = FRESH differs from COMMITTED by exactly DELTA; 1 = it does
#                        not (the report names every pair); 2 = malformed; 3 = DELTA is inert here
#     --rebase-delta DELTA NEWBASE [OUT]  carry DELTA over to the manifest NEWBASE when no declared
#                        pair's FROM side moved there (#1264): the same rows, base_sha256 and
#                        result_sha256 recomputed, exactly what --emit-expected would write against
#                        NEWBASE. 0 = written to OUT (or stdout); 1 = refused, every overlapping pair
#                        named; 2 = malformed. scripts/land.sh applies it to a stale delta at PHASE 2.
#                        The result is a hypothesis: NEWBASE's code may run the rows differently, and
#                        only a walk (the gate, or land.sh's PHASE 3b pre-walk) decides it
#       --rebase-from OLDBASE  first require DELTA's rows to rebuild its own result_sha256 on OLDBASE,
#                        the manifest it was predicted against (1 when they do not: the change moves a
#                        header line or the row order, which no rebase can carry). land.sh always gives it
#     --delta-self-test  the predicted-delta decider's planted self-test alone
#
#   With scripts/corpus.expected-delta present and LIVE (its base_sha256 is the committed manifest),
#   --check passes exactly when the fresh walk realises the declared delta, and says so on a
#   `match by the declared delta` line: the oracle commit is then OWED, and the fresh manifest it
#   left at target/corpus-manifest/corpus.manifest is that oracle, byte for byte. An absent, spent or
#   stale delta leaves --check exactly as it was: the manifest must match.
#
#   ALATYR_CORPUS_CC        absolute compiler to exercise (default: this checkout's target/debug/alatyr)
#   ALATYR_CORPUS_TIMEOUT   seconds per child process, build phases included (default: 30)
#   ALATYR_CORPUS_JOBS      sources in flight (default: min(nproc, 8); 1 = serial)
#   ALATYR_CORPUS_KEEP=1    keep every artifact for inspection instead of freeing it per source
#   ALATYR_CORPUS_ALLOW_FOREIGN_CC=1   permit an ALATYR_CORPUS_CC that is not this checkout's compiler
#   ALATYR_CORPUS_REOBSERVE=0          do NOT re-observe a timed-out source serially before classifying
#                                      it. An EVIDENCE knob: it reproduces the pre-#537 behaviour in
#                                      which one starved child was reported as a NO-LONGER-RUNS
#                                      regression. A gate never sets it.
set -u
export LC_ALL=C
ulimit -c 0 2>/dev/null || true

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

## Every path handed to a tool is RELATIVE to $ROOT (which is the cwd from here on). That is not a
## style choice: it is what keeps a tool diagnostic — and a corpus program's argv[0] — free of this
## checkout's location. Never make WORK absolute.
WORK=target/corpus-manifest

# ---------------------------------------------------------------------------------------------------
# Quarantined (source × backend) pairs.
#
# A pair listed here is NOT observed, and the count is printed on every run so the exclusion can never
# be silent. The list is checked against the corpus: naming a fixture that is no longer tracked is a
# hard failure, so an exclusion cannot rot into a lie.
#
# The list is EMPTY today, and the reason it exists is worth keeping. Three `reject_*` fixtures —
# reject_agg_arg_scalar_param, reject_enum_local_as_scalar, reject_return_enum_as_scalar — used to be
# ACCEPTED and emitted by the non-x86 surface (the fail-open emit path), and the emitted programs read
# UNINITIALIZED STACK: their exit status was whatever the guest's initial stack happened to hold, which
# was measured to move with the length of the ELF's path (`argv[0]` len 11 → 208, 40 → 144, 70 → 80)
# and with the size of the environment (aarch64: 145 under a normal env, 17 under `env -i`). They were
# quarantined on aarch64/riscv64 for exactly that reason. `main` has since closed the root cause — the
# three non-x86 emit surfaces type-check before they emit — and all three now stop at `compile 1` with
# a located diagnostic on every backend, so there is nothing left to quarantine and the coverage is
# back. Re-measured on this base, not assumed.
#
# Reach for this list only for a pair whose observable result is genuinely UNDEFINED, never to silence
# a row that is merely inconvenient, and never to "fix" a fixture: `test/` correctness is not this
# gate's business.
# ---------------------------------------------------------------------------------------------------
EXCLUDE_PAIRS=()

is_excluded() { # rel backend -> 0 when the pair is quarantined
  local rel="$1" backend="$2" e
  for e in "${EXCLUDE_PAIRS[@]}"; do
    set -- $e
    [ "$1" = "$rel" ] && [ "$2" = "$backend" ] && return 0
  done
  return 1
}

excluded_for_source() { # rel -> how many of its four backends are quarantined
  local rel="$1" n=0 e
  for e in "${EXCLUDE_PAIRS[@]}"; do
    set -- $e
    [ "$1" = "$rel" ] && n=$((n + 1))
  done
  printf '%s' "$n"
}

# ---------------------------------------------------------------------------------------------------
# Observation helpers (used by the worker; they read the exported environment set up by the parent).
# ---------------------------------------------------------------------------------------------------

## sha256 of one captured stream, after collapsing the three host-specific spellings that a tool
## diagnostic can still smuggle in. The first sed range confines the offset rewrite to wasmtime's
## explicit backtrace block; the remaining -E substitutions normalize paths. The three path regexes
## are pre-escaped by the parent (WORK_RE / ROOT_RE / HOME_RE) because a checkout path contains
## regex metacharacters.
## The `<artifact>` rule is load-bearing, not cosmetic. A tool diagnostic names the file it was given —
## `ld.bfd: target/corpus-manifest/x86_64/000176/prog.o: in function 'main':`, `wasmtime: failed to run
## main module 'target/corpus-manifest/wasm/000100/prog.wasm'` — and that path carries the source's
## INDEX in the corpus. Hashing it makes every row after an added or deleted fixture move: measured,
## untracking one fixture and adding two changed 3 250 lines, 3 242 of them rows that had nothing to do
## with the change. A behaviour oracle that churns whenever the corpus grows is not usable, so the
## artifact prefix collapses to a fixed token and the row's `path` column carries the identity instead.
## And one more class of host noise, found the same way: wasmtime prints a BACKTRACE for a trapping module,
## and each frame carries a code OFFSET inside the module — `    1:    0x133 - <unknown>!<wasm function 6>`.
## Those offsets move with any emission change, so a trapping wasm program's row moved while its exit stayed
## 134 and its stdout stayed empty (measured: `test/compiles_value_query.al`, 0x131 -> 0x133, its three other
## backend rows byte-identical). Only the offset is collapsed, and only inside a line shaped like a wasmtime
## frame, so a program printing its own hex to stderr is still fully observed. The `<wasm function N>` index
## in the same line is deliberately NOT collapsed: it changes only if the emitted function COUNT changes,
## which is a real observation about the compiler and not host noise.
normalize_stream() {
  sed -E \
         -e '/error while executing at wasm backtrace:/,/^[[:space:]]+[0-9]+:[[:space:]]+wasm trap:/ s|^([[:space:]]+[0-9]+:[[:space:]]+)0x[[:xdigit:]]+([[:space:]]+-[[:space:]]+<unknown>!<wasm function [0-9]+>[[:space:]]*)$|\1<wasmoff>\2|' \
         -e 's|/nix/store/[0-9a-z]{32}-|/nix/store/<hash>-|g' \
         -e "s|$WORK_RE/[a-z0-9_]+/[0-9]{6}/|<artifact>/|g" \
         -e "s|$ROOT_RE|<root>|g" \
         -e "s|$HOME_RE|<home>|g" \
         "$1"
}

hash_stream() {
  normalize_stream "$1" | sha256sum | cut -d' ' -f1
}

record() { # backend rel phase exit stdout-file stderr-file
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$1" "$2" "$3" "$4" "$(hash_stream "$5")" "$(hash_stream "$6")" >> "$ROWFILE"
}

## One build step (compile / assemble / link), bounded by the SAME timeout as a program run. The first
## cut wrapped only the program run, so a looping compiler wedged the gate with no progress output.
## A timeout is reported as its own phase — `compile_timeout` is not `compile 124`.
## Sets PHASE; returns the child's exit status.
step() { # phase stdout-file stderr-file -- cmd...
  local phase="$1" out="$2" err="$3"; shift 3
  timeout "$TIMEOUT_SECS" "$@" >"$out" 2>"$err" </dev/null
  local rc=$?
  PHASE="$phase"
  [ "$rc" -eq 124 ] && PHASE="${phase}_timeout"
  return "$rc"
}

## Run one corpus program. The timeout supervisor and the guest must have separate stderr streams:
## timeout's "dumped core" report describes how the supervisor reaped the child, not guest behaviour.
## The small wrapper execs the guest immediately, so argv, stdout, environment, exit status and timeout
## semantics stay the same; only the guest's stderr is written to the stream that gets hashed. The
## subshell's own stderr is discarded so that bash's "Trace/breakpoint trap" report for a child that
## died by signal — an EXPECTED terminal result here, the non-x86 backends fail loud on unsupported
## shapes — never reaches the gate's output. The environment is fixed (see the header): only these four
## variables, never the host's.
run_prog() { # stdout-file stderr-file -- cmd...
  local out="$1" err="$2"; shift 2
  local supervisor_err="${err}.timeout"
  ( exec 2>/dev/null
    timeout "$TIMEOUT_SECS" env -i LC_ALL=C TZ=UTC HOME=/nonexistent PATH=/usr/bin:/bin \
      /bin/sh -c 'child_err="$1"; shift; exec "$@" 2>"$child_err"' \
      corpus-manifest-child "$err" "$@" >"$out" 2>"$supervisor_err" </dev/null )
  return $?
}

obs_x86() { # rel id
  local rel="$1" id="$2" d="$WORK/x86_64/$2"
  mkdir -p "$d"
  if step compile "$d/c.out" "$d/c.err" "$CC" -o "$d/prog" "$rel"; then
    run_prog "$d/r.out" "$d/r.err" "./$d/prog"
    record x86_64 "$rel" run "$?" "$d/r.out" "$d/r.err"
  else
    record x86_64 "$rel" "$PHASE" "$?" "$d/c.out" "$d/c.err"
  fi
}

## aarch64 and riscv64 share their shape exactly; `emit` is the compiler's backend argument, and the
## emitted GAS is this pair's `stdout` for the compile phase.
obs_gas() { # rel id backend emit as ld runner
  local rel="$1" id="$2" backend="$3" emit="$4" xas="$5" xld="$6" runner="$7" d="$WORK/$3/$2"
  mkdir -p "$d"
  step compile "$d/prog.s" "$d/c.err" "$CC" "$emit" "$rel" \
    || { record "$backend" "$rel" "$PHASE" "$?" "$d/prog.s" "$d/c.err"; return; }
  step assemble "$d/a.out" "$d/a.err" "$xas" "$d/prog.s" -o "$d/prog.o" \
    || { record "$backend" "$rel" "$PHASE" "$?" "$d/a.out" "$d/a.err"; return; }
  step link "$d/l.out" "$d/l.err" "$xld" "$d/prog.o" -o "$d/prog.elf" \
    || { record "$backend" "$rel" "$PHASE" "$?" "$d/l.out" "$d/l.err"; return; }
  run_prog "$d/r.out" "$d/r.err" "$runner" "$d/prog.elf"
  record "$backend" "$rel" run "$?" "$d/r.out" "$d/r.err"
}

## wasm's instantiate failure, told from a program that ran. wasmtime reports a module it could not
## instantiate as `Error: failed to run main module …` / `Caused by: 0: failed to instantiate "…"` /
## `1: unknown import: \`env::sym\` has not been defined`, and exits 1 WITHOUT ever reaching `_start`; a
## program that traps prints `wasm trap` and exits 134, and a program that returns 1 leaves stderr to its
## own output. Those three are different facts and the manifest must not write them with one word, so the
## test is wasmtime's own wording and nothing else. The residual risk is a guest that prints this exact
## phrasing and exits nonzero — it would be filed under `link` while it ran; the stderr hash still records
## it, so the row would move and be seen rather than silently agree.
wasm_link_failed() { # stderr-file
  grep -qE 'failed to instantiate|unknown import:' "$1"
}

obs_wasm() { # rel id
  local rel="$1" id="$2" d="$WORK/wasm/$2"
  mkdir -p "$d"
  step compile "$d/prog.wat" "$d/c.err" "$CC" wat "$rel" \
    || { record wasm "$rel" "$PHASE" "$?" "$d/prog.wat" "$d/c.err"; return; }
  step assemble "$d/a.out" "$d/a.err" "$WAT2WASM" "$d/prog.wat" -o "$d/prog.wasm" \
    || { record wasm "$rel" "$PHASE" "$?" "$d/a.out" "$d/a.err"; return; }
  ## `-C cache=n`: under the fixed environment wasmtime would otherwise try to create
  ## $HOME/.cache/wasmtime and FAIL — measured, that turned all 1 235 wasm `run` rows into a uniform
  ## `exit 1, cache directory permission denied`, i.e. a column that recorded nothing about any
  ## program while still passing a "the backend reached phase run" check. Disabling the cache also
  ## removes a directory two lanes would otherwise share.
  run_prog "$d/r.out" "$d/r.err" "$WASMTIME" -C cache=n "$d/prog.wasm"
  local rrc=$?
  ## A wasmtime exit that comes from a module which never INSTANTIATED is not a program answer. wasm has
  ## no `link` step of its own — the twins get theirs from `ld` — so instantiate IS wasm's link, and a
  ## refusal there belongs in the `link` phase the vocabulary already carries for the other backends.
  ## Recorded as `run` instead, an unresolved `@extern` import (Modules §7.2) reads as "wasm ran and
  ## quietly returned 1 where x86_64 returned 42": a silent wrong value that never happened. Measured on
  ## the committed manifest, 34 of the 37 wasm `run` rows at exit 1 are this, and they are the whole of
  ## the cross-backend quiet-disagreement set outside the four hardware-defined `unchecked` divisions.
  if [ "$rrc" != 0 ] && wasm_link_failed "$d/r.err"; then
    record wasm "$rel" link "$rrc" "$d/r.out" "$d/r.err"
    return
  fi
  record wasm "$rel" run "$rrc" "$d/r.out" "$d/r.err"
}

## One unit of parallel work: all four backends for one source, in the fixed backend order, into one
## row file named by the source's index. The parent concatenates the row files in index order, so the
## manifest's row order does not depend on ALATYR_CORPUS_JOBS.
worker_main() {
  local id rel
  IFS=$'\t' read -r id rel <<< "$1"
  ROWFILE="$WORK/rows/$id"
  : > "$ROWFILE"
  is_excluded "$rel" x86_64  || obs_x86 "$rel" "$id"
  is_excluded "$rel" aarch64 || obs_gas "$rel" "$id" aarch64 aarch64 "$A64_AS" "$A64_LD" "$QEMU_A64"
  is_excluded "$rel" riscv64 || obs_gas "$rel" "$id" riscv64 riscv64 "$RV64_AS" "$RV64_LD" "$QEMU_RV64"
  is_excluded "$rel" wasm    || obs_wasm "$rel" "$id"
  [ "${KEEP:-0}" = 1 ] || rm -rf "$WORK/x86_64/$id" "$WORK/aarch64/$id" "$WORK/riscv64/$id" "$WORK/wasm/$id"
  return 0
}

if [ "${1:-}" = "--worker" ]; then
  worker_main "$2"
  exit $?
fi

# ===================================================================================================
# Parent
# ===================================================================================================

MODE=check
MANIFEST="$ROOT/scripts/corpus.manifest"
## 30 s, not 10: the ceiling exists to stop a LOOPING compiler, not to police compile time, and with
## eight sources in flight a 10 s ceiling left a margin small enough that a busy machine could turn a
## spurious `compile_timeout` into a RED gate — the worst failure mode for a committed baseline.
##
## The margin, RE-MEASURED on this tree rather than carried forward: `alatyr -o … test/uint256.al` is
## 6.78 s unloaded and `test/u128_div.al` is 2.55 s, while EVERY other (source × backend) pair of the
## 8 000 is ≤ 0.11 s — uint256 itself is 25 ms to `check` and ~50 ms to emit aarch64/riscv64/wat GAS, so
## the whole cost is the x86_64 assemble-and-link. Two pairs out of 8 000 therefore carry the entire
## timeout exposure, at a 4.4× and an 11.8× margin. The note this replaces claimed 2.2 s and a 13×
## margin; that measurement aged out, which is exactly why the SAME file breached the ceiling twice in
## issue #537. Raising the number again would age out too. The answer is not the ceiling but the
## re-observation below: a row that hits it is TESTED for looping instead of assumed to be looping.
TIMEOUT_SECS="${ALATYR_CORPUS_TIMEOUT:-30}"
REOBSERVE="${ALATYR_CORPUS_REOBSERVE:-1}"
KEEP="${ALATYR_CORPUS_KEEP:-0}"
JOBS="${ALATYR_CORPUS_JOBS:-}"
if [ -z "$JOBS" ]; then
  JOBS="$(nproc 2>/dev/null || echo 1)"
  [ "$JOBS" -gt 8 ] && JOBS=8
fi

usage() { sed -n '/^# ## Usage/,/^set -u/p' "$SELF" | sed -e 's/^# \{0,1\}//' -e '$d'; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) MODE=check ;;
    --write) MODE=write ;;
    --self-test) MODE=selftest ;;
    --explain)
      [ "$#" -ge 3 ] || { echo "corpus manifest: --explain needs two manifest files" >&2; exit 2; }
      MODE=explain; EXPLAIN_A="$2"; EXPLAIN_B="$3"; shift 2 ;;
    --emit-expected)
      [ "$#" -ge 3 ] || { echo "corpus manifest: --emit-expected needs the committed and the fresh manifest" >&2; exit 2; }
      MODE=emit-expected; EXPLAIN_A="$2"; EXPLAIN_B="$3"; shift 2 ;;
    --check-delta)
      [ "$#" -ge 4 ] || { echo "corpus manifest: --check-delta needs the committed manifest, the fresh one and a delta file" >&2; exit 2; }
      MODE=check-delta; EXPLAIN_A="$2"; EXPLAIN_B="$3"; DELTA_ARG="$4"; shift 3 ;;
    --rebase-delta)
      [ "$#" -ge 3 ] || { echo "corpus manifest: --rebase-delta needs a delta file and the new base manifest" >&2; exit 2; }
      MODE=rebase-delta; DELTA_ARG="$2"; EXPLAIN_A="$3"; REBASE_OUT=; shift 2
      case "${2:-}" in ''|--*) ;; *) REBASE_OUT="$2"; shift ;; esac ;;
    --rebase-from)
      [ "$#" -ge 2 ] || { echo "corpus manifest: --rebase-from needs the manifest the delta was predicted against" >&2; exit 2; }
      REBASE_FROM="$2"; shift ;;
    --delta-self-test) MODE=delta-selftest ;;
    --help|-h) usage; exit 0 ;;
    *) echo "corpus manifest: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

die() { echo "corpus manifest: $*" >&2; exit 2; }

# ===================================================================================================
# The JOIN, the predicted delta, and the modes that need no compiler.
#
# Everything from here to the tool checks below is pure manifest arithmetic: it reads two or three
# text files and runs no compiler, no cross tool and no program. So these modes are dispatched BEFORE
# the toolchain is resolved — `--explain` used to resolve all eight cross tools and build a compiler
# it never ran — and they work on a machine with no `nix develop` at all.
# ===================================================================================================
TAB="$(printf '\t')"

sha_file() { # file -> its sha256
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

## THE CLASSIFIER — the one place a (backend, path) transition gets its name. `--explain`, the
## predicted delta's emitter and its checker all read these rows, so a declared expectation and an
## observed transition are compared in the same vocabulary by construction, never by two copies of
## the rules that could drift apart.
##
## Join two manifests on (backend, path) and print one TAB row per differing pair:
##   class <TAB> backend <TAB> path <TAB> before <TAB> after
## where before/after are `phase/exit/stdout_sha256/stderr_sha256`, or `-` for an absent pair.
## Sorted on (backend, path) so that the output is a function of the two inputs alone.
## Reading the raw `diff -u` positionally is WRONG and has nearly cost a landing: added and removed
## rows do not pair up, so a shifted row invents transitions that are not there, and a global `head`
## can truncate away an entire severity class. Eight `run -> assemble/1` regressions once sat inside
## 23 genuine wins.
delta_rows() { # baseline candidate
  awk 'BEGIN { FS = "\t"; OFS = "\t" }
function emit(c, k, ov, nv,   kk) { split(k, kk, SUBSEP); print c, kk[1], kk[2], ov, nv }
## `side`, set by an operand assignment, and neither FNR == NR (an EMPTY baseline would read the
## candidate as the baseline) nor FILENAME (the SAME file given twice would be read as two baselines).
side == 1 {
  if (NF == 6 && $1 ~ /^(x86_64|aarch64|riscv64|wasm)$/) o[$1 SUBSEP $2] = $3 "/" $4 "/" $5 "/" $6
  next
}
NF == 6 && $1 ~ /^(x86_64|aarch64|riscv64|wasm)$/ { n[$1 SUBSEP $2] = $3 "/" $4 "/" $5 "/" $6 }
END {
  for (k in o) if (!(k in n)) emit("REMOVED", k, o[k], "-")
  for (k in n) {
    if (!(k in o)) { emit("ADDED", k, "-", n[k]); continue }
    if (o[k] == n[k]) continue
    split(o[k], a, "/"); split(n[k], b, "/")
    orun = (a[1] == "run"); nrun = (b[1] == "run")
    ## A `*_timeout` in the FRESH run gets its own class, ahead of every other test. It is not a
    ## regression class: `rc == 124 after the ceiling` says the child did not finish, and nothing about
    ## it says the compiler refused the program. Folding it into NO-LONGER-RUNS reported a conclusion
    ## the stage had disclaimed in the same output (issue #537); the walk now re-observes such a row
    ## serially first, so one that reaches here has breached the ceiling twice.
    if (b[1] ~ /_timeout$/)        c = "TIMED-OUT"
    ## Same exit, earlier phase: NOTHING about the observed behaviour changed — only the word for where
    ## the program stopped. Calling that NO-LONGER-RUNS asserts a regression the row cannot support, and
    ## it did: 34 wasm rows moved `run/1 -> link/1` when the walk began recording an uninstantiated module
    ## as the link failure it always was, and the report called all 34 regressions of programs that had
    ## never run. A real stop-running has a value to lose, so it shows as an exit change; an identical
    ## exit is a recording correction, and it is named as one so review looks at the cause, not the count.
    else if (orun && !nrun && a[2] == b[2]) c = "PHASE-CHANGED"
    else if (orun && !nrun)        c = "NO-LONGER-RUNS"
    else if (!orun && nrun)        c = "NOW-RUNS"
    else if (orun && a[2] != b[2]) c = "EXIT-CHANGED"
    else if (orun)                 c = "OUTPUT-CHANGED"
    else if (a[1] != b[1])         c = "PHASE-CHANGED"
    else                           c = "DETAIL-CHANGED"
    emit(c, k, o[k], n[k])
  }
}' side=1 "$1" side=2 "$2" | sort -t "$TAB" -k2,2 -k3,3
}

## Join two manifests on (backend, path) and print each difference under its severity class.
## `--explain <old> <new>` exposes it directly; `--check` calls it on a mismatch. EXPLAIN_CAP
## bounds the sample PER CLASS, never globally: a global bound can hide a whole class.
EXPLAIN_CAP="${ALATYR_CORPUS_EXPLAIN_CAP:-12}"
explain_manifest() { # baseline candidate
  delta_rows "$1" "$2" | awk -v CAP="$EXPLAIN_CAP" 'BEGIN { FS = "\t" }
{
  total++; c = $1; cnt[c]++; bk[c SUBSEP $2]++
  if (shown[c] + 0 < CAP) {
    split($4, a, "/"); split($5, b, "/")
    smp[c] = smp[c] sprintf("      %-8s %-52s %s -> %s\n", $2, $3, \
      ($4 == "-" ? "-" : a[1] "/" a[2]), ($5 == "-" ? "-" : b[1] "/" b[2]))
    shown[c]++
  }
}
END {
  nc = split("TIMED-OUT NO-LONGER-RUNS EXIT-CHANGED REMOVED PHASE-CHANGED DETAIL-CHANGED OUTPUT-CHANGED NOW-RUNS ADDED", ord, " ")
  desc["TIMED-OUT"]      = "did not finish inside the per-child ceiling — a HANG, or a machine loaded from outside this gate"
  desc["NO-LONGER-RUNS"] = "was running, now refused by an earlier phase — a REGRESSION"
  desc["EXIT-CHANGED"]   = "ran before and after, different exit — a VALUE change"
  desc["REMOVED"]        = "the pair is gone from the fresh run — coverage lost"
  desc["PHASE-CHANGED"]  = "stopped at a different phase with the SAME exit — a recording correction, not a behaviour change (it covers a run that never ran now filed as the link failure it was)"
  desc["DETAIL-CHANGED"] = "same phase, different exit or captured streams"
  desc["OUTPUT-CHANGED"] = "ran with the same exit, different stdout/stderr"
  desc["NOW-RUNS"]       = "was refused, now runs — a WIN"
  desc["ADDED"]          = "new pair in the fresh run — new coverage"
  if (total == 0) { print "corpus manifest: no (backend,path) pair differs"; exit 0 }
  printf "corpus manifest: %d differing pairs, joined on (backend, path)\n", total
  nb = split("x86_64 aarch64 riscv64 wasm", bo, " ")
  for (i = 1; i <= nc; i++) {
    c = ord[i]; if (!(c in cnt)) continue
    line = ""
    for (j = 1; j <= nb; j++) if ((c SUBSEP bo[j]) in bk) line = line sprintf(" %s %d", bo[j], bk[c SUBSEP bo[j]])
    printf "\n  %-15s %4d pair(s)  [%s ]\n      %s\n", c, cnt[c], line, desc[c]
    printf "%s", smp[c]
    if (cnt[c] > shown[c]) printf "      … %d more in this class (the count above is complete)\n", cnt[c] - shown[c]
  }
}'
}

# ---------------------------------------------------------------------------------------------------
# THE PREDICTED DELTA (`scripts/corpus.expected-delta`).
#
# An intentional behaviour change used to cost TWO full gates: the first one went red on the expected
# manifest mismatch, the maintainer committed the regenerated oracle, and the whole gate ran again on
# an object whose only new byte was the oracle. That second run could only ever differ from the first
# in the two stages that READ the manifest as data — this one and the `xbackend_diff.sh` ratchet —
# because an oracle commit changes no source byte, and the fixpoint, e2e, the sweeps, the formatter,
# the idiom/strict-form/wildcard checks and the IR verifier are functions of the source tree alone.
#
# So the feature PR now DECLARES the manifest shift it causes, in a file that is part of the gated
# object and is reviewed in the PR's diff (it is deliberately not `-diff`, unlike the manifest). The
# gate then asks the stronger question "is the fresh-vs-committed difference EXACTLY the declared
# one?" — no undeclared pair, no unrealised one, every declared value equal to the observed one, down
# to the stream hashes — and the fresh manifest it generated IS the oracle, which `scripts/land.sh`
# commits byte for byte and checks with `cmp`, not with a second walk.
#
#   # comments
#   format=alatyr-corpus-delta-v1
#   base_sha256=<sha256 of the committed scripts/corpus.manifest the prediction was made against>
#   result_sha256=<sha256 of the whole manifest the change produces>
#   pairs=<number of rows below>
#   columns=class<TAB>backend<TAB>path<TAB>before<TAB>after
#   <delta_rows row> …
#
# The rows are `delta_rows` output verbatim: the class is `--explain`'s, and before/after are the full
# `phase/exit/stdout/stderr` of the pair, so an expectation and an observation compare as text.
#
# A delta is LIVE only while the committed manifest is byte-identical to the one it names in
# `base_sha256`. Once the oracle commit it predicted has landed, or once any other oracle moves under
# it, it is INERT and the plain byte-for-byte match is required again — so a delta left behind on
# `main` can never make a later mismatch pass, and a stale prediction can only ever turn a gate red.
# Write one with `--emit-expected`; never by hand. A stale one whose declared pairs the other change did
# not touch is carried to the new base by `--rebase-delta` (#1264): the same rows, the two hashes
# recomputed. scripts/land.sh does that at PHASE 2 and lands the rebased copy.
# ---------------------------------------------------------------------------------------------------
DELTA_FORMAT=alatyr-corpus-delta-v1
DELTA_FILE_REL=scripts/corpus.expected-delta

delta_field() { sed -n "s/^$2=//p" "$1" | head -n 1; }    # delta-file key

## A file is a usable manifest for this purpose: the v2 marker, and a row_count its body agrees with.
## (The delta arithmetic is not the gate of the gate — `check_body_shape` is — but a delta computed
## against a truncated file would declare the truncation.)
manifest_usable() { # file label
  local declared actual
  [ -f "$1" ] || { echo "corpus delta: no such manifest: $1" >&2; return 2; }
  grep -qx 'format=alatyr-corpus-manifest-v2' "$1" ||
    { echo "corpus delta: $2 $1 is not an alatyr-corpus-manifest-v2 file" >&2; return 2; }
  declared="$(sed -n 's/^row_count=//p' "$1" | head -n 1)"
  actual="$(awk -F'\t' 'NF==6 && $1 ~ /^(x86_64|aarch64|riscv64|wasm)$/ {n++} END{print n+0}' "$1")"
  [ "${declared:-x}" = "$actual" ] ||
    { echo "corpus delta: $2 $1 is inconsistent: row_count=${declared:-<absent>} but it holds $actual rows" >&2; return 2; }
  return 0
}

## Write the delta that takes <committed> to <fresh>, on stdout. Refuses (rc 2) a TIMED-OUT pair — a
## contention artifact must never be declared as the intended behaviour — and (rc 1) an empty delta,
## which is not a prediction of anything and would only make the plain match harder to read.
emit_expected() { # committed fresh
  local rows timed
  manifest_usable "$1" committed || return 2
  manifest_usable "$2" fresh || return 2
  rows="$(delta_rows "$1" "$2")"
  if [ -z "$rows" ]; then
    echo "corpus delta: no (backend, path) pair differs between $1 and $2 — there is nothing to declare." >&2
    echo "  A change that moves no row needs no delta file; do not commit an empty one." >&2
    return 1
  fi
  timed="$(printf '%s\n' "$rows" | awk -F'\t' '$1 == "TIMED-OUT"' | grep -c '' || true)"
  if [ "$timed" != 0 ]; then
    echo "corpus delta: REFUSED — $timed pair(s) in $2 are TIMED-OUT. A timeout is a measurement that did" >&2
    echo "  not finish, not a behaviour; re-run the walk on a quiet machine before predicting anything." >&2
    printf '%s\n' "$rows" | awk -F'\t' '$1 == "TIMED-OUT" {print "    " $2 "  " $3}' >&2
    return 2
  fi
  printf '# Alatyr predicted corpus-manifest delta; generated by scripts/corpus_manifest.sh --emit-expected.\n'
  printf '# The feature PR declares the transitions it causes; the gate requires the fresh manifest to differ\n'
  printf '# from the committed one by EXACTLY these rows, and scripts/land.sh then commits that fresh manifest as\n'
  printf '# the oracle. Inert once the committed manifest is no longer base_sha256. Regenerate, never hand-edit.\n'
  printf '%s\n' "$rows" | awk -F'\t' '{c[$1]++; b[$1 FS $2]++}
    END {
      n = split("TIMED-OUT NO-LONGER-RUNS EXIT-CHANGED REMOVED PHASE-CHANGED DETAIL-CHANGED OUTPUT-CHANGED NOW-RUNS ADDED", o, " ")
      m = split("x86_64 aarch64 riscv64 wasm", bo, " ")
      for (i = 1; i <= n; i++) if (o[i] in c) {
        s = ""; for (j = 1; j <= m; j++) if ((o[i] FS bo[j]) in b) s = s " " bo[j] " " b[o[i] FS bo[j]]
        printf "#   %-15s %4d pair(s)  [%s ]\n", o[i], c[o[i]], s
      }
    }'
  printf 'format=%s\n' "$DELTA_FORMAT"
  printf 'base_sha256=%s\n' "$(sha_file "$1")"
  printf 'result_sha256=%s\n' "$(sha_file "$2")"
  printf 'pairs=%s\n' "$(printf '%s\n' "$rows" | grep -c '')"
  printf 'columns=class<TAB>backend<TAB>path<TAB>before<TAB>after\n'
  printf '%s\n' "$rows"
  return 0
}

## The delta file's rows, sorted the way `delta_rows` sorts — or rc 2 with the reason on stderr when
## the file is not a well-formed v1 delta. Everything that is not a comment, a known header key or a
## five-field row is a refusal: a parser that skipped what it did not understand could be fed a row it
## silently ignored.
delta_declared_rows() { # delta-file
  awk -F'\t' -v FMT="$DELTA_FORMAT" '
    /^#/ || /^$/ { next }
    /^(format|base_sha256|result_sha256|pairs|columns)=/ && NF == 1 { next }
    NF == 5 && $1 ~ /^(TIMED-OUT|NO-LONGER-RUNS|EXIT-CHANGED|REMOVED|PHASE-CHANGED|DETAIL-CHANGED|OUTPUT-CHANGED|NOW-RUNS|ADDED)$/ \
            && $2 ~ /^(x86_64|aarch64|riscv64|wasm)$/ && $3 != "" && $4 != "" && $5 != "" { print; next }
    { printf "corpus delta: line %d of %s is neither a header nor a delta row: %s\n", NR, FILENAME, $0 > "/dev/stderr"; bad = 1 }
    END { exit bad ? 2 : 0 }' "$1" > "$1.rows.$$" || { rm -f "$1.rows.$$"; return 2; }
  sort -t "$TAB" -k2,2 -k3,3 "$1.rows.$$"
  rm -f "$1.rows.$$"
}

## THE DECIDER. Returns
##   0  LIVE and REALISED — <fresh> differs from <committed> by exactly the declared rows, and is the
##      byte-exact manifest the delta names in result_sha256;
##   1  LIVE and NOT realised — the report lists every UNDECLARED, UNREALISED and MISPREDICTED pair;
##   2  the delta or a manifest is malformed (a refusal, never an inert pass);
##   3  INERT — the committed manifest is not the delta's base, so the delta says nothing here. Sets
##      DELTA_STATE to `spent` (the committed manifest IS the predicted result: the oracle landed) or
##      `stale` (some other oracle).
## Reads only its arguments, so the self-test drives the real decision on synthetic files.
DELTA_STATE=
DELTA_PAIRS=
## Read a delta file into <dir>/declared (its rows, sorted) and DELTA_BASE / DELTA_RESULT /
## DELTA_PAIRS, or rc 2 with the reason on stderr. The one reader of the file's header and rows: the
## decider below and the rebase (`delta_rebase`) must refuse exactly the same malformed files.
DELTA_BASE=
DELTA_RESULT=
delta_parse() { # delta-file work-dir
  local delta="$1" dir="$2" fmt base result pairs n
  DELTA_BASE=; DELTA_RESULT=; DELTA_PAIRS=
  [ -f "$delta" ] || { echo "corpus delta: no such delta file: $delta" >&2; return 2; }
  fmt="$(delta_field "$delta" format)"
  [ "$fmt" = "$DELTA_FORMAT" ] ||
    { echo "corpus delta: $delta is not an $DELTA_FORMAT file (format=${fmt:-<absent>})" >&2; return 2; }
  base="$(delta_field "$delta" base_sha256)"; result="$(delta_field "$delta" result_sha256)"
  pairs="$(delta_field "$delta" pairs)"
  case "$base" in *[!0-9a-f]*|'') base=bad ;; esac
  case "$result" in *[!0-9a-f]*|'') result=bad ;; esac
  if [ "${#base}" != 64 ] || [ "${#result}" != 64 ]; then
    echo "corpus delta: $delta must name base_sha256 and result_sha256 as 64 hex digits" >&2; return 2
  fi
  case "$pairs" in ''|*[!0-9]*) echo "corpus delta: $delta has no numeric pairs= line" >&2; return 2 ;; esac
  cp "$delta" "$dir/delta"
  delta_declared_rows "$dir/delta" > "$dir/declared" || return 2
  n="$(grep -c '' < "$dir/declared" || true)"
  if [ "$n" != "$pairs" ] || [ "$n" = 0 ]; then
    echo "corpus delta: $delta declares pairs=$pairs but holds $n row(s)" >&2; return 2
  fi
  if awk -F'\t' '$1 == "TIMED-OUT" {f = 1} END {exit !f}' "$dir/declared"; then
    echo "corpus delta: $delta declares a TIMED-OUT pair. A timeout is never an intended behaviour;" >&2
    echo "  regenerate the delta from a walk that finished." >&2
    return 2
  fi
  DELTA_BASE="$base"; DELTA_RESULT="$result"; DELTA_PAIRS="$n"
  return 0
}

delta_check() { # committed fresh delta-file
  local committed="$1" fresh="$2" delta="$3" base result csha fsha tmp n
  DELTA_STATE=malformed; DELTA_PAIRS=
  manifest_usable "$committed" committed || return 2
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/corpus-delta.XXXXXX")" || return 2
  delta_parse "$delta" "$tmp" || { rm -rf "$tmp"; DELTA_PAIRS=; return 2; }
  base="$DELTA_BASE"; result="$DELTA_RESULT"; n="$DELTA_PAIRS"
  csha="$(sha_file "$committed")"
  if [ "$csha" != "$base" ]; then
    if [ "$csha" = "$result" ]; then DELTA_STATE=spent; else DELTA_STATE=stale; fi
    rm -rf "$tmp"; return 3
  fi
  DELTA_STATE=live
  manifest_usable "$fresh" fresh || { rm -rf "$tmp"; return 2; }
  delta_rows "$committed" "$fresh" > "$tmp/observed"
  if cmp -s "$tmp/declared" "$tmp/observed"; then
    fsha="$(sha_file "$fresh")"
    rm -rf "$tmp"
    [ "$fsha" = "$result" ] && return 0
    echo "corpus delta: every declared row was observed, but the fresh manifest is not the one the delta" >&2
    echo "  names (sha256 $fsha, declared result_sha256 $result) — its header or row order moved." >&2
    return 1
  fi
  awk -F'\t' '
    function v(s,   x) { if (s == "-") return "-"; split(s, x, "/"); return x[1] "/" x[2] " out:" substr(x[3], 1, 8) " err:" substr(x[4], 1, 8) }
    side == 1 { d[$2 FS $3] = $0; next }
    { o[$2 FS $3] = $0 }
    END {
      ## rank TAB backend TAB path TAB text (the key holds FS itself), sorted and cut, so the order of the report is a function of its inputs.
      for (k in o) if (!(k in d)) { split(o[k], r, FS); nu++
        printf "1\t%s\t  UNDECLARED    %-8s %-46s observed %s  %s -> %s\n", k, r[2], r[3], r[1], v(r[4]), v(r[5]) }
      for (k in d) if (!(k in o)) { split(d[k], r, FS); nr++
        printf "2\t%s\t  UNREALISED    %-8s %-46s declared %s  %s -> %s\n", k, r[2], r[3], r[1], v(r[4]), v(r[5]) }
      for (k in o) if ((k in d) && d[k] != o[k]) { split(d[k], r, FS); split(o[k], q, FS); nm++
        printf "3\t%s\t  MISPREDICTED  %-8s %-46s declared %s  %s -> %s\n", k, r[2], r[3], r[1], v(r[4]), v(r[5])
        printf "3\t%s\t  %-13s %-8s %-46s observed %s  %s -> %s\n", k "~", "", "", "", q[1], v(q[4]), v(q[5]) }
      printf "9\t~\t~\tcorpus delta: %d undeclared, %d unrealised, %d mispredicted pair(s)\n", nu, nr, nm
    }' side=1 "$tmp/declared" side=2 "$tmp/observed" | sort -t "$TAB" -k1,1 -k3,3 -k2,2 | cut -f4- > "$tmp/report"
  echo "corpus delta: the fresh manifest does NOT differ from the committed one by exactly the declared delta" >&2
  echo "  ($delta, $n declared pair(s)). Joined on (backend, path):" >&2
  grep -v '^corpus delta:' "$tmp/report" >&2
  grep '^corpus delta:' "$tmp/report" >&2
  echo "  An undeclared pair is a behaviour change nobody predicted; an unrealised one is a predicted change" >&2
  echo "  that did not happen. Either is a red gate: fix the change, or regenerate the delta with" >&2
  echo "  --emit-expected and read its rows in the PR diff before the next gate." >&2
  rm -rf "$tmp"
  return 1
}

## THE REBASE (#1264). A delta names the manifest it was predicted against, so every other oracle
## commit made it stale: with N delta PRs in flight, each landing sent the other N-1 back for a rebase
## and a fresh native walk, although none of them touched the rows that moved.
##
## A rebased delta is a HYPOTHESIS, and the gate tests it. Text alone decides only that the two
## predictions do not collide in the manifest:
##   every declared pair's FROM side is the new base's row for that (backend, path), or, for a declared
##   ADDED pair, the new base has no row for it.
## It cannot decide that the TO side still holds. The rows were measured by running the PR's fixtures
## on the code of the PR's old base, and the other landing changed main's CODE, not only its manifest.
## That change can move what the PR's own new or changed fixtures do without moving any row the
## manifest held. #1215 is the case: #1227's guard, on main, turned #1215's new fixture's run/7 into
## run/132-134, and the four mechanically rebased ADDED rows still said run/7. So a disjoint rebase can
## still be a red gate.
##
## When the FROM sides hold, the rows carry over VERBATIM and only the two hashes are recomputed:
## base_sha256 is the new base, and result_sha256 is the new base with exactly the declared transitions
## applied. The output is what `--emit-expected <new-base> <result>` writes, byte for byte. That is how
## it is built: the result manifest is assembled, then emitted and compared with the declared rows.
## When any declared FROM side differs, the other change moved a row this one predicts. That is a
## refusal naming every such pair, never a guess.
##
## Nothing gets weaker. The gate still demands that the fresh walk realise the rebased delta exactly,
## result_sha256 included, so a wrong hypothesis is a red gate (MISPREDICTED) and never a silent pass.
## scripts/land.sh walks the corpus alone first (PHASE 3b) when it rebased a delta, so a wrong one costs
## minutes, not a full gate.
##
## The result's row order is the walk's: sources sorted bytewise (`git ls-files | sort` under the gate's
## C collation), then backend_order within a source. The rebase checks that the new base is already in
## that order before it inserts a row into it, and refuses when it is not, rather than predicting a
## file the walk would not write. Every header line except source_count and row_count is copied from
## the new base.
##
## A delta whose result is not "the base with these rows changed", one that adds a header line or
## reorders the file, cannot be carried over this way. Given the manifest the delta was predicted
## against (<old-base>, whose sha256 must be base_sha256), the rebase first rebuilds result_sha256 there
## from the rows alone, and refuses when it cannot. That check refuses, before any walk, a rebase whose
## result_sha256 would be wrong even if every row still held. It says nothing about whether the rows
## hold on the new code; see the hypothesis above. scripts/land.sh always supplies <old-base>, from
## main's history.
##   0  rebased; the new delta is on stdout, or in <out> when given
##   1  refused: an overlapping pair (each named), a result the rows alone do not rebuild on <old-base>,
##      or the new base IS the delta's result (spent)
##   2  malformed input, an <old-base> that is not the delta's base, or a base the rebase cannot place
##      rows in

## <base> with the declared transitions applied, written to <out>: TO `-` drops the pair, any other TO
## replaces or adds it, in the walk's row order; source_count and row_count recounted, every other header
## line copied. rc 2 when <base> is not in the walk's order or its source_count is not its own.
delta_apply() { # declared-rows base out work-dir
  local declared="$1" base="$2" out="$3" w="$4"
  awk -F'\t' 'BEGIN { OFS = "\t"; split("x86_64 aarch64 riscv64 wasm", o, " "); for (i = 1; i <= 4; i++) bi[o[i]] = i }
    NF == 6 && ($1 in bi) { print $2, bi[$1], $0 }' "$base" > "$w/keyed"
  LC_ALL=C sort -t "$TAB" -k1,1 -k2,2n "$w/keyed" | cmp -s - "$w/keyed" || {
    echo "corpus delta: REFUSED — the rows of $base are not in the walk's order (sources sorted bytewise," >&2
    echo "  then backend_order), so a rebased row could not be placed where a walk writes it." >&2
    return 2; }
  awk -F'\t' 'NF == 6 && $1 ~ /^(x86_64|aarch64|riscv64|wasm)$/ { n++; if (!($2 in s)) { s[$2]; p++ } }
              /^source_count=/ { sc = substr($0, 14) } END { exit !(n > 0 && sc == p) }' "$base" || {
    echo "corpus delta: REFUSED — source_count= in $base is not the number of sources its rows name." >&2
    return 2; }
  awk -F'\t' 'BEGIN { OFS = "\t"; split("x86_64 aarch64 riscv64 wasm", o, " "); for (i = 1; i <= 4; i++) bi[o[i]] = i }
    side == 1 { t[$2 FS $3] = $5; next }
    { k = $3 FS $4 } (k in t) { seen[k]; if (t[k] != "-") { split(t[k], v, "/"); print $1, $2, $3, $4, v[1], v[2], v[3], v[4] }; next }
    { print }
    END { for (k in t) if (!(k in seen) && t[k] != "-") { split(k, kk, FS); split(t[k], v, "/")
            print kk[2], bi[kk[1]], kk[1], kk[2], v[1], v[2], v[3], v[4] } }
  ' side=1 "$declared" side=2 "$w/keyed" | LC_ALL=C sort -t "$TAB" -k1,1 -k2,2n | cut -f3- > "$w/body"
  awk -F'\t' -v ROWS="$(grep -c '' < "$w/body")" -v SRCS="$(cut -f2 "$w/body" | sort -u | grep -c '')" '
    NF == 6 && $1 ~ /^(x86_64|aarch64|riscv64|wasm)$/ { exit }
    /^source_count=/ { print "source_count=" SRCS; next }
    /^row_count=/ { print "row_count=" ROWS; next }
    { print }' "$base" > "$out"
  cat "$w/body" >> "$out"
}

## Every declared pair whose FROM side is not <base>'s row, one CONFLICT line each; nothing when none.
delta_conflicts() { # declared-rows base
  awk -F'\t' '
    side == 1 { if (NF == 6 && $1 ~ /^(x86_64|aarch64|riscv64|wasm)$/) b[$1 FS $2] = $3 "/" $4 "/" $5 "/" $6; next }
    { k = $2 FS $3; cur = (k in b) ? b[k] : "-"
      if ($4 != cur) printf "  CONFLICT  %-8s %-46s %-15s declared FROM %s, the new base holds %s\n", $2, $3, $1, $4, cur }
  ' side=1 "$2" side=2 "$1"
}

delta_rebase() { # delta-file new-base [out] [old-base]
  local delta="$1" nb="$2" out="${3:-}" ob="${4:-}" tmp nsha conflicts
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/corpus-rebase.XXXXXX")" || return 2
  delta_parse "$delta" "$tmp" || { rm -rf "$tmp"; return 2; }
  manifest_usable "$nb" "new base" || { rm -rf "$tmp"; return 2; }
  if [ -n "$ob" ]; then
    manifest_usable "$ob" "old base" || { rm -rf "$tmp"; return 2; }
    [ "$(sha_file "$ob")" = "$DELTA_BASE" ] && [ -z "$(delta_conflicts "$tmp/declared" "$ob")" ] || {
      echo "corpus delta: $ob is not the manifest $delta was predicted against (base_sha256)" >&2
      rm -rf "$tmp"; return 2; }
    delta_apply "$tmp/declared" "$ob" "$tmp/rebuilt" "$tmp" || { rm -rf "$tmp"; return 2; }
    [ "$(sha_file "$tmp/rebuilt")" = "$DELTA_RESULT" ] || {
      echo "corpus delta: REFUSED — $delta cannot be carried to another base: its rows applied to its own" >&2
      echo "  base do not rebuild its result_sha256, so the change moves more of the manifest than its rows" >&2
      echo "  (a header line, the row order). Only a fresh walk of the rebased branch (--emit-expected) can" >&2
      echo "  predict it. Rebuilt $(sha_file "$tmp/rebuilt" | cut -c1-12), declared $(printf '%s' "$DELTA_RESULT" | cut -c1-12)." >&2
      rm -rf "$tmp"; return 1; }
  fi
  nsha="$(sha_file "$nb")"
  if [ "$nsha" = "$DELTA_RESULT" ]; then
    echo "corpus delta: REFUSED — $nb IS the manifest $delta predicts (result_sha256): the delta is spent," >&2
    echo "  its oracle commit has landed, and there is nothing left to rebase." >&2
    rm -rf "$tmp"; return 1
  fi
  conflicts="$(delta_conflicts "$tmp/declared" "$nb")"
  if [ -n "$conflicts" ]; then
    echo "corpus delta: REFUSED — $delta cannot be rebased onto $nb: $(printf '%s\n' "$conflicts" | grep -c '') of" >&2
    echo "  its $DELTA_PAIRS declared pair(s) start from a row the new base no longer holds. Another change moved" >&2
    echo "  what this one predicts; only a fresh walk of the rebased branch (--emit-expected) can answer:" >&2
    printf '%s\n' "$conflicts" >&2
    rm -rf "$tmp"; return 1
  fi
  delta_apply "$tmp/declared" "$nb" "$tmp/result" "$tmp" || { rm -rf "$tmp"; return 2; }
  ## Built, not trusted: the emitter must see exactly the declared rows between the two manifests.
  emit_expected "$nb" "$tmp/result" > "$tmp/rebased" 2>"$tmp/emit.err" &&
    delta_declared_rows "$tmp/rebased" > "$tmp/redeclared" 2>>"$tmp/emit.err" &&
    cmp -s "$tmp/declared" "$tmp/redeclared" || {
    echo "corpus delta: REFUSED — the rebased result does not reproduce the declared rows when emitted" >&2
    echo "  against $nb; this is a defect of the rebase, not of the delta:" >&2
    sed 's/^/  /' "$tmp/emit.err" >&2
    diff "$tmp/declared" "$tmp/redeclared" 2>/dev/null | head -n 8 | sed 's/^/  /' >&2
    rm -rf "$tmp"; return 2; }
  if [ -n "$out" ]; then cp "$tmp/rebased" "$out.tmp.$$" && mv "$out.tmp.$$" "$out" || { rm -rf "$tmp"; return 2; }
  else cat "$tmp/rebased"; fi
  echo "corpus delta: REBASED — $DELTA_PAIRS pair(s), none overlapping; base $(printf '%s' "$DELTA_BASE" | cut -c1-12) -> $(printf '%s' "$nsha" | cut -c1-12)," >&2
  echo "  result $(delta_field "$tmp/rebased" result_sha256 | cut -c1-12); the rows are the original's verbatim$([ -n "$ob" ] && echo ', and they rebuild its own result on its own base' || echo '; NOT checked against its own base (no old base given)')" >&2
  rm -rf "$tmp"
  return 0
}

## The predicted delta's own gate of the gate. Synthetic manifests, no compiler, no walk: every way the
## decider must refuse, planted, and the controls it must accept — an always-refusing decider loses
## the controls, an always-accepting one loses the plants. Run on every `--check`/`--self-test` and by
## `--delta-self-test` alone (which is also what `scripts/land.sh --self-test` drives).
CM_DELTA_SELFTEST_EXPECTED=60
delta_selftest() { # work-dir
  local st="$1" bad="" k=0 out rc
  rm -rf "$st"; mkdir -p "$st" || return 1
  _dk() { k=$((k+1)); [ "$1" = 0 ] || bad="$bad $2"; }
  _mf() { # out-file body-file -- wraps a body in the v2 header
    { printf '# synthetic\nformat=alatyr-corpus-manifest-v2\nsource_glob=test/*.al\n'
      printf 'source_count=%s\n' "$(awk -F'\t' '$1=="x86_64"' "$2" | grep -c '')"
      printf 'backend_order=x86_64,aarch64,riscv64,wasm\nexcluded_pairs=0\n'
      printf 'row_count=%s\n' "$(grep -c '' < "$2")"
      printf 'columns=backend<TAB>path<TAB>phase<TAB>exit<TAB>stdout_sha256<TAB>stderr_sha256\n'
      cat "$2"; } > "$1"
  }
  local h0 h1 h2 e0
  h0=0000000000000000000000000000000000000000000000000000000000000000
  h1=1111111111111111111111111111111111111111111111111111111111111111
  h2=2222222222222222222222222222222222222222222222222222222222222222
  e0=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
  awk -v H="$h1" -v E="$e0" 'BEGIN { OFS = "\t"
    split("a b c d", f, " "); split("x86_64 aarch64 riscv64 wasm", b, " ")
    for (j = 1; j <= 4; j++) for (i = 1; i <= 4; i++) {
      ph = "run"; ex = 42
      if (f[j] == "b" && b[i] != "x86_64") { ph = "assemble"; ex = 1 }
      print b[i], "test/" f[j] ".al", ph, ex, H, E } }' > "$st/base.body"
  _mf "$st/base" "$st/base.body"
  ## The intended change: test/b.al now RUNS on the three twins (133, a trap), test/c.al answers 7 on
  ## wasm, and a new fixture test/e.al adds its four rows.
  awk -F'\t' -v E="$e0" 'BEGIN { OFS = "\t" }
    $2 == "test/b.al" && $1 != "x86_64" { $3 = "run"; $4 = 133 }
    $2 == "test/c.al" && $1 == "wasm"   { $4 = 7 }
    { print }
    END { split("x86_64 aarch64 riscv64 wasm", b, " ")
          for (i = 1; i <= 4; i++) print b[i], "test/e.al", "run", 42, "3333333333333333333333333333333333333333333333333333333333333333", E }' \
    "$st/base.body" > "$st/fresh.body"
  _mf "$st/fresh" "$st/fresh.body"

  # 1 · the emitter writes a v1 delta, and it is the classifier's rows.
  emit_expected "$st/base" "$st/fresh" > "$st/delta" 2>"$st/e"; rc=$?
  [ "$rc" = 0 ]; _dk $? "emit-refused-a-real-change(rc=$rc: $(cat "$st/e"))"
  [ "$(delta_field "$st/delta" pairs)" = 8 ]; _dk $? "emit-miscounted(pairs=$(delta_field "$st/delta" pairs), want 3+1+4)"
  [ "$(awk -F'\t' '$1=="NOW-RUNS"' "$st/delta" | grep -c '')" = 3 ] &&
  [ "$(awk -F'\t' '$1=="EXIT-CHANGED"' "$st/delta" | grep -c '')" = 1 ] &&
  [ "$(awk -F'\t' '$1=="ADDED"' "$st/delta" | grep -c '')" = 4 ]
  _dk $? emit-did-not-use-the-explain-classes
  out="$(explain_manifest "$st/base" "$st/fresh")"
  case "$out" in *'8 differing pairs'*'EXIT-CHANGED       1 pair(s)'*'NOW-RUNS           3 pair(s)'*'ADDED              4 pair(s)'*) _dk 0 x ;;
                 *) _dk 1 "explain-and-the-delta-disagree($out)" ;; esac

  # 2 · CONTROL: the declared change, observed exactly, is accepted.
  delta_check "$st/base" "$st/fresh" "$st/delta" 2>"$st/e"; rc=$?
  [ "$rc" = 0 ]; _dk $? "check-refused-an-exactly-realised-delta(rc=$rc: $(cat "$st/e"))"
  [ "$DELTA_STATE" = live ] && [ "$DELTA_PAIRS" = 8 ]; _dk $? "check-misreported-state($DELTA_STATE/$DELTA_PAIRS)"

  # 3 · nothing happened: the fresh run equals the committed manifest, the delta is live. Every
  #     declared pair is unrealised, so this must be RED — a plain `cmp` would have called it a match.
  out="$(delta_check "$st/base" "$st/base" "$st/delta" 2>&1)"; rc=$?
  [ "$rc" = 1 ]; _dk $? "check-accepted-a-live-delta-on-an-unchanged-manifest(rc=$rc)"
  case "$out" in *'0 undeclared, 8 unrealised, 0 mispredicted'*) _dk 0 x ;; *) _dk 1 "unrealised-not-counted($out)" ;; esac

  # 4 · an UNDECLARED pair: the delta forgets one row the change moved.
  grep -v "^EXIT-CHANGED${TAB}" "$st/delta" | sed 's/^pairs=8$/pairs=7/' > "$st/d.short"
  out="$(delta_check "$st/base" "$st/fresh" "$st/d.short" 2>&1)"; rc=$?
  [ "$rc" = 1 ]; _dk $? "check-accepted-an-undeclared-pair(rc=$rc)"
  case "$out" in *'UNDECLARED    wasm     test/c.al'*'1 undeclared, 0 unrealised'*) _dk 0 x ;;
                 *) _dk 1 "undeclared-pair-not-named($out)" ;; esac

  # 5 · an UNREALISED pair: the delta predicts one more row than moved.
  { cat "$st/delta"; printf 'NOW-RUNS\tx86_64\ttest/a.al\tcompile/1/%s/%s\trun/42/%s/%s\n' "$h1" "$e0" "$h1" "$e0"; } |
    sed 's/^pairs=8$/pairs=9/' > "$st/d.long"
  out="$(delta_check "$st/base" "$st/fresh" "$st/d.long" 2>&1)"; rc=$?
  [ "$rc" = 1 ]; _dk $? "check-accepted-an-unrealised-pair(rc=$rc)"
  case "$out" in *'UNREALISED    x86_64   test/a.al'*) _dk 0 x ;; *) _dk 1 "unrealised-pair-not-named($out)" ;; esac

  # 6 · MISPREDICTED: right pair, wrong value — the exit, then (same phase/exit) only a stream hash.
  sed "s|^\(EXIT-CHANGED${TAB}wasm${TAB}test/c.al${TAB}.*${TAB}run/\)7/|\18/|" "$st/delta" > "$st/d.exit"
  cmp -s "$st/delta" "$st/d.exit"; [ $? = 1 ]; _dk $? selftest-failed-to-plant-a-wrong-exit
  out="$(delta_check "$st/base" "$st/fresh" "$st/d.exit" 2>&1)"; rc=$?
  [ "$rc" = 1 ]; _dk $? "check-accepted-a-wrong-exit(rc=$rc)"
  case "$out" in *'MISPREDICTED  wasm     test/c.al'*) _dk 0 x ;; *) _dk 1 "misprediction-not-named($out)" ;; esac
  sed "s|^\(ADDED${TAB}wasm${TAB}test/e.al${TAB}-${TAB}run/42/\)3333|\14444|" "$st/delta" > "$st/d.hash"
  cmp -s "$st/delta" "$st/d.hash"; [ $? = 1 ]; _dk $? selftest-failed-to-plant-a-wrong-hash
  delta_check "$st/base" "$st/fresh" "$st/d.hash" >/dev/null 2>&1
  [ $? = 1 ]; _dk $? check-accepted-a-pair-whose-only-difference-is-a-stream-hash
  # …and a class relabelled without its values (EXIT-CHANGED declared as OUTPUT-CHANGED).
  sed "s|^EXIT-CHANGED${TAB}|OUTPUT-CHANGED${TAB}|" "$st/delta" > "$st/d.class"
  delta_check "$st/base" "$st/fresh" "$st/d.class" >/dev/null 2>&1
  [ $? = 1 ]; _dk $? check-accepted-a-relabelled-class

  # 7 · every row realised, but the result is not the declared object (a header that moved).
  sed "s/^result_sha256=.*/result_sha256=$h2/" "$st/delta" > "$st/d.result"
  out="$(delta_check "$st/base" "$st/fresh" "$st/d.result" 2>&1)"; rc=$?
  [ "$rc" = 1 ]; _dk $? "check-accepted-a-fresh-manifest-that-is-not-result_sha256(rc=$rc)"

  # 8 · INERT, both ways, and inert is never a pass by itself: the caller still needs a match.
  delta_check "$st/fresh" "$st/fresh" "$st/delta" >/dev/null 2>&1; rc=$?
  [ "$rc" = 3 ] && [ "$DELTA_STATE" = spent ]; _dk $? "check-did-not-call-a-landed-delta-spent(rc=$rc state=$DELTA_STATE)"
  sed "s/^base_sha256=.*/base_sha256=$h2/" "$st/delta" > "$st/d.stale"
  delta_check "$st/base" "$st/fresh" "$st/d.stale" >/dev/null 2>&1; rc=$?
  [ "$rc" = 3 ] && [ "$DELTA_STATE" = stale ]; _dk $? "check-did-not-call-a-foreign-base-stale(rc=$rc state=$DELTA_STATE)"

  # 9 · malformed is a refusal (rc 2), never inert.
  sed 's/^pairs=8$/pairs=5/' "$st/delta" > "$st/d.count"
  delta_check "$st/base" "$st/fresh" "$st/d.count" >/dev/null 2>&1; [ $? = 2 ]; _dk $? check-accepted-a-wrong-pairs-count
  sed "s/^format=.*/format=alatyr-corpus-delta-v0/" "$st/delta" > "$st/d.fmt"
  delta_check "$st/base" "$st/fresh" "$st/d.fmt" >/dev/null 2>&1; [ $? = 2 ]; _dk $? check-accepted-an-unknown-format
  { cat "$st/delta"; echo 'this line is not a row'; } > "$st/d.junk"
  delta_check "$st/base" "$st/fresh" "$st/d.junk" >/dev/null 2>&1; [ $? = 2 ]; _dk $? check-skipped-a-line-it-did-not-understand
  sed "s/^NOW-RUNS${TAB}aarch64/BETTER${TAB}aarch64/" "$st/delta" > "$st/d.vocab"
  delta_check "$st/base" "$st/fresh" "$st/d.vocab" >/dev/null 2>&1; [ $? = 2 ]; _dk $? check-accepted-a-class-outside-the-explain-vocabulary
  sed '/^base_sha256=/d' "$st/delta" > "$st/d.nobase"
  delta_check "$st/base" "$st/fresh" "$st/d.nobase" >/dev/null 2>&1; [ $? = 2 ]; _dk $? check-accepted-a-delta-with-no-base

  # 10 · a TIMED-OUT pair is never declarable: the emitter refuses it and the checker refuses it.
  awk -F'\t' 'BEGIN{OFS="\t"} $1=="x86_64" && $2=="test/d.al" {$3="compile_timeout"; $4=124} {print}' "$st/fresh.body" > "$st/to.body"
  _mf "$st/to" "$st/to.body"
  emit_expected "$st/base" "$st/to" > "$st/d.to" 2>/dev/null; [ $? = 2 ]; _dk $? emit-declared-a-TIMED-OUT-pair
  { sed 's/^pairs=8$/pairs=9/' "$st/delta"
    printf 'TIMED-OUT\tx86_64\ttest/d.al\trun/42/%s/%s\tcompile_timeout/124/%s/%s\n' "$h1" "$e0" "$h1" "$e0"; } > "$st/d.to2"
  delta_check "$st/base" "$st/to" "$st/d.to2" >/dev/null 2>&1; [ $? = 2 ]; _dk $? check-accepted-a-declared-TIMED-OUT-pair

  # 11 · nothing to declare is not a delta, and a truncated manifest is not a fresh run.
  emit_expected "$st/base" "$st/base" > /dev/null 2>&1; [ $? = 1 ]; _dk $? emit-wrote-an-empty-delta
  head -n 12 "$st/fresh" > "$st/trunc"
  emit_expected "$st/base" "$st/trunc" > /dev/null 2>&1; [ $? = 2 ]; _dk $? emit-accepted-a-truncated-fresh-manifest
  delta_check "$st/base" "$st/trunc" "$st/delta" > /dev/null 2>&1; [ $? = 2 ]; _dk $? check-accepted-a-truncated-fresh-manifest

  # 12 · REMOVED and PHASE-CHANGED/DETAIL-CHANGED round-trip too (a deleted fixture, a moved refusal).
  awk -F'\t' 'BEGIN{OFS="\t"} $2=="test/d.al" {next} $2=="test/b.al" && $1=="aarch64" {$3="link"} $2=="test/b.al" && $1=="riscv64" {$4=2} {print}' \
    "$st/base.body" > "$st/rm.body"
  _mf "$st/rm" "$st/rm.body"
  emit_expected "$st/base" "$st/rm" > "$st/d.rm" 2>/dev/null; rc=$?
  [ "$rc" = 0 ] && [ "$(awk -F'\t' '$1=="REMOVED"' "$st/d.rm" | grep -c '')" = 4 ] &&
    [ "$(awk -F'\t' '$1=="PHASE-CHANGED"' "$st/d.rm" | grep -c '')" = 1 ] &&
    [ "$(awk -F'\t' '$1=="DETAIL-CHANGED"' "$st/d.rm" | grep -c '')" = 1 ]
  _dk $? "emit-misclassified-removals-or-refusal-moves(rc=$rc)"
  delta_check "$st/base" "$st/rm" "$st/d.rm" >/dev/null 2>&1; [ $? = 0 ]; _dk $? check-refused-a-realised-removal-delta
  # …and one delta cannot license another change: the removal delta against the feature's fresh run.
  delta_check "$st/base" "$st/fresh" "$st/d.rm" >/dev/null 2>&1; [ $? = 1 ]; _dk $? check-accepted-another-changes-delta

  # 13 · the emitter's output is deterministic (row order is a function of the inputs alone).
  emit_expected "$st/base" "$st/fresh" > "$st/delta2" 2>/dev/null
  cmp -s "$st/delta" "$st/delta2"; _dk $? emit-is-not-deterministic

  # 14 · THE REBASE (#1264). Another change's oracle landed under the delta. Each expected manifest
  #      below is written out row by row, never derived by the code under test.
  local x
  x="$(printf '\t')"
  # 14a · a DISJOINT move: test/a.al now answers 9 on wasm, and a new fixture test/aa.al (sorting
  #       between a and b, so the rebase must insert rows mid-file) adds four rows.
  awk -F'\t' -v H="$h1" -v E="$e0" 'BEGIN { OFS = "\t" }
    $2 == "test/a.al" && $1 == "wasm" { $4 = 9 }
    { print }
    $2 == "test/a.al" && $1 == "wasm" { split("x86_64 aarch64 riscv64 wasm", b, " "); for (i = 1; i <= 4; i++) print b[i], "test/aa.al", "run", 5, H, E }' \
    "$st/base.body" > "$st/b2.body"
  _mf "$st/b2" "$st/b2.body"
  # …and the walk of the rebased branch, by hand: b2 with this delta's transitions, e.al last.
  awk -F'\t' -v E="$e0" 'BEGIN { OFS = "\t" }
    $2 == "test/b.al" && $1 != "x86_64" { $3 = "run"; $4 = 133 }
    $2 == "test/c.al" && $1 == "wasm"   { $4 = 7 }
    { print }
    END { split("x86_64 aarch64 riscv64 wasm", b, " ")
          for (i = 1; i <= 4; i++) print b[i], "test/e.al", "run", 42, "3333333333333333333333333333333333333333333333333333333333333333", E }' \
    "$st/b2.body" > "$st/f2.body"
  _mf "$st/f2" "$st/f2.body"
  delta_check "$st/b2" "$st/f2" "$st/delta" >/dev/null 2>&1; rc=$?
  [ "$rc" = 3 ]; _dk $? "selftest-the-stale-delta-is-not-inert-on-the-moved-base(rc=$rc)"
  delta_rebase "$st/delta" "$st/b2" "$st/d.rebased" 2>"$st/e"; rc=$?
  [ "$rc" = 0 ] && [ -f "$st/d.rebased" ]; _dk $? "rebase-refused-a-disjoint-delta(rc=$rc: $(cat "$st/e"))"
  delta_check "$st/b2" "$st/f2" "$st/d.rebased" >/dev/null 2>"$st/e"; rc=$?
  [ "$rc" = 0 ]; _dk $? "check-refused-the-rebased-delta-on-the-realised-walk(rc=$rc: $(cat "$st/e"))"
  [ "$(delta_field "$st/d.rebased" base_sha256)" = "$(sha_file "$st/b2")" ] &&
    [ "$(delta_field "$st/d.rebased" result_sha256)" = "$(sha_file "$st/f2")" ]
  _dk $? rebase-did-not-recompute-both-hashes
  grep -v -e '^base_sha256=' -e '^result_sha256=' "$st/delta" > "$st/r.a"
  grep -v -e '^base_sha256=' -e '^result_sha256=' "$st/d.rebased" > "$st/r.b" 2>/dev/null
  cmp -s "$st/r.a" "$st/r.b"; _dk $? rebase-changed-more-than-the-two-hashes
  emit_expected "$st/b2" "$st/f2" 2>/dev/null | cmp -s - "$st/d.rebased"; _dk $? rebase-is-not-what-emit-expected-writes-on-the-new-base
  # 14b · the identity: a LIVE delta rebased onto its own base is itself, byte for byte (the header and
  #       row placement are rebuilt, and must land on the manifest the walk wrote).
  delta_rebase "$st/delta" "$st/base" 2>/dev/null | cmp -s - "$st/delta"; _dk $? rebase-onto-its-own-base-is-not-the-identity
  # 14c · REMOVED pairs: a deleted fixture moves source_count and row_count in the rebased result.
  awk -F'\t' 'BEGIN{OFS="\t"} $2=="test/d.al" {next} $2=="test/b.al" && $1=="aarch64" {$3="link"} $2=="test/b.al" && $1=="riscv64" {$4=2} {print}' \
    "$st/b2.body" > "$st/rm2.body"
  _mf "$st/rm2" "$st/rm2.body"
  delta_rebase "$st/d.rm" "$st/b2" "$st/d.rm2" 2>/dev/null &&
    delta_check "$st/b2" "$st/rm2" "$st/d.rm2" >/dev/null 2>&1
  _dk $? rebase-mishandled-a-removal-delta
  # 14d · an OVERLAP: the other change moved test/c.al on wasm too (42 -> 5). Refused, pair named,
  #       nothing written.
  sed "s/^\(wasm${x}test\/c.al${x}run${x}\)42${x}/\15${x}/" "$st/base" > "$st/b3"
  cmp -s "$st/base" "$st/b3"; [ $? = 1 ]; _dk $? selftest-failed-to-plant-an-overlap
  rm -f "$st/d.over"
  out="$(delta_rebase "$st/delta" "$st/b3" "$st/d.over" 2>&1)"; rc=$?
  [ "$rc" = 1 ] && [ ! -e "$st/d.over" ]; _dk $? "rebase-accepted-an-overlapping-delta(rc=$rc)"
  case "$out" in *'CONFLICT  wasm     test/c.al'*'declared FROM run/42/'*'the new base holds run/5/'*) _dk 0 x ;;
                 *) _dk 1 "overlap-pair-not-named($out)" ;; esac
  case "$out" in *'test/b.al'*|*'test/e.al'*) _dk 1 "rebase-named-a-pair-that-does-not-overlap" ;; *) _dk 0 x ;; esac
  # 14e · an ADDED pair whose path the new base already holds: test/e.al landed elsewhere first.
  { cat "$st/base.body"
    for b in x86_64 aarch64 riscv64 wasm; do printf '%s\ttest/e.al\trun\t1\t%s\t%s\n' "$b" "$h1" "$e0"; done; } > "$st/b4.body"
  _mf "$st/b4" "$st/b4.body"
  out="$(delta_rebase "$st/delta" "$st/b4" 2>&1)"; rc=$?
  [ "$rc" = 1 ]; _dk $? "rebase-accepted-an-ADDED-pair-the-base-already-holds(rc=$rc)"
  case "$out" in *'4 of'*'CONFLICT  aarch64  test/e.al'*'ADDED'*'declared FROM -, the new base holds run/1/'*) _dk 0 x ;;
                 *) _dk 1 "added-pair-not-named($out)" ;; esac
  # 14f · spent, malformed and out-of-order inputs are refusals, never a rebase.
  delta_rebase "$st/delta" "$st/fresh" >/dev/null 2>&1; [ $? = 1 ]; _dk $? rebase-accepted-a-spent-delta
  delta_rebase "$st/d.count" "$st/b2" >/dev/null 2>&1; [ $? = 2 ]; _dk $? rebase-accepted-a-malformed-delta
  #       Rows the emitter would never write, rebased with NO old base, so only the built-not-trusted net
  #       (emit the result, compare the rows) stands between them and an output file: a duplicate
  #       (backend, path) row with pairs= bumped to match, and an ADDED row relabelled NOW-RUNS.
  awk -F'\t' '{ print } $1 == "ADDED" && $2 == "wasm" { print }' "$st/delta" | sed 's/^pairs=8$/pairs=9/' > "$st/d.dup"
  [ "$(grep -c "^ADDED${x}wasm${x}test/e.al${x}" "$st/d.dup")" = 2 ]; _dk $? selftest-failed-to-plant-a-duplicate-row
  rm -f "$st/d.dup2"
  delta_rebase "$st/d.dup" "$st/b2" "$st/d.dup2" >/dev/null 2>&1; rc=$?
  [ "$rc" = 2 ] && [ ! -e "$st/d.dup2" ]; _dk $? "rebase-carried-a-duplicate-row-without-an-old-base(rc=$rc)"
  sed "s/^ADDED${x}wasm${x}/NOW-RUNS${x}wasm${x}/" "$st/delta" > "$st/d.lbl"
  rm -f "$st/d.lbl2"
  delta_rebase "$st/d.lbl" "$st/b2" "$st/d.lbl2" >/dev/null 2>&1; rc=$?
  [ "$rc" = 2 ] && [ ! -e "$st/d.lbl2" ]; _dk $? "rebase-carried-a-mislabelled-row-without-an-old-base(rc=$rc)"
  { sed -n '1,/^columns=/p' "$st/b2"; sed '1,/^columns=/d' "$st/b2" | LC_ALL=C sort -r; } > "$st/b5"
  delta_rebase "$st/delta" "$st/b5" >/dev/null 2>&1; [ $? = 2 ]; _dk $? rebase-placed-rows-in-a-base-that-is-not-in-walk-order
  # 14g · a change that also moves a HEADER line (its result has a `scope=` line its base lacks). The
  #       rows alone cannot carry that, so given its own base the rebase refuses it; a delta whose rows
  #       do rebuild its result passes the same check; a wrong old base is malformed input.
  awk '{ print } $0 == "format=alatyr-corpus-manifest-v2" { print "scope=planted" }' "$st/fresh" > "$st/fh"
  grep -qx 'scope=planted' "$st/fh"; _dk $? selftest-failed-to-plant-a-header-line
  emit_expected "$st/base" "$st/fh" > "$st/d.hdr" 2>/dev/null
  out="$(delta_rebase "$st/d.hdr" "$st/b2" "$st/d.hdr2" "$st/base" 2>&1)"; rc=$?
  [ "$rc" = 1 ] && [ ! -e "$st/d.hdr2" ]; _dk $? "rebase-carried-a-delta-whose-rows-do-not-rebuild-its-result(rc=$rc)"
  case "$out" in *'cannot be carried to another base'*) _dk 0 x ;; *) _dk 1 "header-move-not-named($out)" ;; esac
  delta_rebase "$st/delta" "$st/b2" "$st/d.rb3" "$st/base" 2>/dev/null && cmp -s "$st/d.rb3" "$st/d.rebased"
  _dk $? rebase-refused-a-delta-whose-rows-rebuild-its-result-on-its-own-base
  delta_rebase "$st/delta" "$st/b2" "$st/d.wrong" "$st/b2" >/dev/null 2>&1; [ $? = 2 ]; _dk $? rebase-took-a-wrong-old-base

  printf '%s' "$bad" > "$st/bad"; printf '%s' "$k" > "$st/checks"; : > "$st/complete"
  unset -f _dk _mf
  if [ -n "$bad" ]; then echo "corpus manifest: predicted-delta self-test FAILED —$bad" >&2; return 1; fi
  if [ "$k" -lt "$CM_DELTA_SELFTEST_EXPECTED" ]; then
    echo "corpus manifest: predicted-delta self-test FAILED — ran $k checks, expected at least $CM_DELTA_SELFTEST_EXPECTED" >&2
    return 1
  fi
  echo "corpus manifest: predicted-delta self-test ok ($k checks — exact realisation accepted; undeclared,"
  echo "  unrealised, mispredicted (exit, hash, class), wrong result, malformed and TIMED-OUT deltas refused;"
  echo "  spent and stale deltas inert; a disjoint stale delta rebased and realised, an overlapping one and"
  echo "  an ADDED pair the new base already holds refused with the pair named)"
  return 0
}

## Run the delta self-test the way the other deciders are run: in a SUBSHELL, verdict read from FILES,
## because an unbound variable inside a driven function unwinds to top level and ends the script.
run_delta_selftest() {
  local st rc
  st="$(mktemp -d "${TMPDIR:-/tmp}/corpus-delta-selftest.XXXXXX")" || return 2
  ( delta_selftest "$st/w" ); rc=$?
  if [ ! -f "$st/w/complete" ]; then
    echo "corpus manifest: the predicted-delta self-test did NOT run to completion (rc=$rc)" >&2; rm -rf "$st"; return 2
  fi
  if [ -s "$st/w/bad" ] || [ "$(cat "$st/w/checks")" -lt "$CM_DELTA_SELFTEST_EXPECTED" ] || [ "$rc" != 0 ]; then
    echo "corpus manifest: the predicted-delta self-test recorded failures —$(cat "$st/w/bad")" >&2; rm -rf "$st"; return 2
  fi
  rm -rf "$st"
  return 0
}

case "$MODE" in
  explain)
    for f in "$EXPLAIN_A" "$EXPLAIN_B"; do [ -f "$f" ] || die "no such manifest: $f"; done
    explain_manifest "$EXPLAIN_A" "$EXPLAIN_B"
    exit 0 ;;
  emit-expected)
    emit_expected "$EXPLAIN_A" "$EXPLAIN_B"
    exit $? ;;
  check-delta)
    delta_check "$EXPLAIN_A" "$EXPLAIN_B" "$DELTA_ARG"; drc=$?
    case "$drc" in
      0) echo "corpus delta: REALISED — $EXPLAIN_B differs from $EXPLAIN_A by exactly the $DELTA_PAIRS declared pair(s)" ;;
      3) echo "corpus delta: INERT ($DELTA_STATE) — $EXPLAIN_A is not the manifest $DELTA_ARG was predicted against" ;;
    esac
    exit "$drc" ;;
  rebase-delta)
    delta_rebase "$DELTA_ARG" "$EXPLAIN_A" "$REBASE_OUT" "${REBASE_FROM:-}"
    exit $? ;;
  delta-selftest)
    run_delta_selftest || exit 2
    exit 0 ;;
esac


for t in sha256sum timeout xargs nproc; do
  command -v "$t" >/dev/null 2>&1 || die "$t is required"
done

## The four backend paths are part of the manifest's contract, so a missing cross toolchain is an
## ENVIRONMENT failure, not a partial green: a three-backend manifest would be silently weaker than the
## artifact it is compared against. (The sweeps' `skip … exit 0` is the wrong shape for a committed
## baseline.) The tools are resolved to absolute paths here, once — the corpus programs run under
## `env -i`, which leaves no PATH for a lookup.
resolve_tool() { # var name
  local v="$1" n="$2" p
  p="$(command -v "$n" 2>/dev/null)" || p=""
  if [ -z "$p" ]; then echo "corpus manifest: required tool not found: $n" >&2; return 1; fi
  printf -v "$v" '%s' "$p" 2>/dev/null || eval "$v=\$p"
  return 0
}
missing=0
if [ "$MODE" != selftest ]; then
  resolve_tool A64_AS  aarch64-unknown-linux-gnu-as || missing=1
  resolve_tool A64_LD  aarch64-unknown-linux-gnu-ld || missing=1
  resolve_tool QEMU_A64 qemu-aarch64                || missing=1
  resolve_tool RV64_AS riscv64-unknown-linux-gnu-as || missing=1
  resolve_tool RV64_LD riscv64-unknown-linux-gnu-ld || missing=1
  resolve_tool QEMU_RV64 qemu-riscv64               || missing=1
  resolve_tool WAT2WASM wat2wasm                    || missing=1
  resolve_tool WASMTIME wasmtime                    || missing=1
  [ "$missing" = 0 ] || die "the manifest describes four backends; it will not report a partial result"
fi

# --- the compiler under test, and why it is the right one ------------------------------------------
newest_src() { find src lib -type f -newer "$1" -print 2>/dev/null | head -n 1; }

PROVENANCE=
if [ -n "${ALATYR_CORPUS_CC:-}" ]; then
  CC="$ALATYR_CORPUS_CC"
  PROVENANCE="ALATYR_CORPUS_CC"
  [ -x "$CC" ] || die "ALATYR_CORPUS_CC is not executable: $CC"
  OWN_CC="$ROOT/target/debug/alatyr"
  if [ ! -x "$OWN_CC" ] && [ -x "$ROOT/target/alatyr" ]; then OWN_CC="$ROOT/target/alatyr"; fi
  ## The comparison below needs this checkout's own compiler to compare AGAINST. If it is absent there
  ## is nothing to check the supplied binary against, so the caller must say out loud that it meant it.
  if [ ! -x "$OWN_CC" ] && [ "${ALATYR_CORPUS_ALLOW_FOREIGN_CC:-0}" != 1 ]; then
    echo "corpus manifest: ALATYR_CORPUS_CC is set but this checkout has no compiler-under-test to compare" >&2
    echo "  it against, so nothing establishes that $CC is this tree's compiler. Build the tree first," >&2
    echo "  or set ALATYR_CORPUS_ALLOW_FOREIGN_CC=1 to measure another binary on purpose." >&2
    exit 2
  fi
  if [ -x "$OWN_CC" ] && [ "$(sha256sum "$CC" | cut -d' ' -f1)" != "$(sha256sum "$OWN_CC" | cut -d' ' -f1)" ]; then
    if [ "${ALATYR_CORPUS_ALLOW_FOREIGN_CC:-0}" != 1 ]; then
      echo "corpus manifest: ALATYR_CORPUS_CC is byte-different from this checkout's compiler-under-test." >&2
      echo "  supplied : $CC" >&2
      echo "  checkout : $OWN_CC" >&2
      echo "  A green manifest would then describe a compiler that is not this tree's. Set" >&2
      echo "  ALATYR_CORPUS_ALLOW_FOREIGN_CC=1 to measure another binary on purpose." >&2
      exit 2
    fi
    PROVENANCE="ALATYR_CORPUS_CC (FOREIGN — not this checkout's compiler-under-test)"
  fi
else
  CC="$ROOT/target/debug/alatyr"
  if [ ! -x "$CC" ] || [ -n "$(newest_src "$CC")" ]; then
    mkdir -p "$ROOT/target"
    blog="$ROOT/target/corpus_manifest_seedbuild.log"
    rm -f "$ROOT/target/alatyr" "$ROOT/target/alatyr.s" "$ROOT/target/alatyr.o"
    rm -f "$ROOT/target/debug/alatyr" "$ROOT/target/debug/alatyr.s" "$ROOT/target/debug/alatyr.o"
    "$ROOT/seed/alatyr" build "$ROOT/package.al" >"$blog" 2>&1 </dev/null
    brc=$?
    if [ "$brc" != 0 ]; then
      echo "corpus manifest: could not build compiler under test from the frozen seed (rc=$brc)" >&2
      sed 's/^/  | /' "$blog" >&2
      exit 2
    fi
    if [ -x "$ROOT/target/debug/alatyr" ]; then
      CC="$ROOT/target/debug/alatyr"
      PROVENANCE="built here by seed/alatyr (target/debug/alatyr)"
    elif [ -x "$ROOT/target/alatyr" ]; then
      CC="$ROOT/target/alatyr"
      PROVENANCE="built here by seed/alatyr (legacy target/alatyr during layout transition)"
      echo "corpus manifest: bootstrap transition — frozen seed used legacy target/alatyr; fixpoint remains the reseed decision" >&2
    else
      echo "corpus manifest: seed created neither target/debug/alatyr nor legacy target/alatyr" >&2
      sed 's/^/  | /' "$blog" >&2
      exit 2
    fi
  else
    PROVENANCE="this checkout's target/debug/alatyr"
  fi
fi
stale="$(newest_src "$CC")"
[ -z "$stale" ] || die "the compiler under test is OLDER than $stale — rebuild it (a green must not be attributable to a stale binary)"
CC_SHA="$(sha256sum "$CC" | cut -d' ' -f1)"
echo "corpus manifest: compiler = $CC"
echo "corpus manifest:   sha256 = $CC_SHA  ($PROVENANCE)"

# --- the corpus ------------------------------------------------------------------------------------
## `git ls-files`, never `find`: an e2e or package run leaves GENERATED .al files under test/ (e.g.
## test/link/statstub/package.al), and an untracked file must not change the row count between runs.
mapfile -t SOURCES < <(git -C "$ROOT" ls-files 'test/*.al' | sort)
SRC_COUNT="${#SOURCES[@]}"
[ "$SRC_COUNT" -gt 0 ] || die "the tracked test/*.al corpus is empty"
for s in "${SOURCES[@]}"; do
  case "$s" in *[[:space:]]*) die "the corpus path '$s' contains whitespace; the TAB-separated job list cannot carry it" ;; esac
done

## Every quarantined pair must name a source that is still tracked, else the exclusion has rotted.
EXCLUDED_PAIRS=0
for e in "${EXCLUDE_PAIRS[@]}"; do
  set -- $e
  found=0
  for s in "${SOURCES[@]}"; do [ "$s" = "$1" ] && found=1 && break; done
  [ "$found" = 1 ] || die "the exclusion list names an untracked fixture: $1 (remove the entry)"
  case "$2" in x86_64|aarch64|riscv64|wasm) ;; *) die "the exclusion list names an unknown backend: $2" ;; esac
  EXCLUDED_PAIRS=$((EXCLUDED_PAIRS + 1))
done
EXPECT_ROWS=$((SRC_COUNT * 4 - EXCLUDED_PAIRS))
echo "corpus manifest: sources = $SRC_COUNT × 4 backends − $EXCLUDED_PAIRS quarantined pairs = $EXPECT_ROWS rows expected"
for e in "${EXCLUDE_PAIRS[@]}"; do echo "corpus manifest:   quarantined: $e"; done

# --- comparison, and the proof that it is alive ----------------------------------------------------
body_rows() { awk -F'\t' 'NF==6 && $1 ~ /^(x86_64|aarch64|riscv64|wasm)$/ {n++} END{print n+0}' "$1"; }

# ---------------------------------------------------------------------------------------------
# THE BODY-SHAPE DECIDER (issue #600) — the one function that decides a finished walk is not a
# manifest. It owns both halves of the gate-of-the-gate the header promises: the ROW-COUNT
# identity (`sources × backends − quarantined`) and the per-backend non-vacuity counters.
#
# Factored out of the walk's inline `if`s so a self-test can drive the real decision. It was this
# stage's uncovered decider — `sweep_check_total`'s exact shape one stage over, and #585's
# consequence too. Measured on the parent with the job list truncated to the first 100 of 2052
# sources: with the row-count refusal turned into a note, `--write` BLESSED a 400-row oracle and
# printed `WROTE … (400 rows, 2052 sources, all four backends ran)` with exit 0. Every per-source
# assertion above it passed — each walked source did produce its four rows — and the four
# non-vacuity counters passed too, because 100 sources still run and still differ. The row count
# is the only thing that can see 95% of the corpus missing, and nothing exercised it.
#
# `wc -l` cannot substitute for it either: the per-source check counts LINES, this counts
# STRUCTURALLY VALID rows, so a worker emitting six-field garbage satisfies the first and not this.
#
# Sets CM_ROWS and the per-backend RUN_<b>/EXIT_<b> counters the report line prints. Returns 0 to
# accept the body, 2 to refuse it — printing, on stderr, which of the three ways it is not a
# manifest. It never exits: the caller owns that, and a self-test must be able to drive a refusal.
check_body_shape() { # body-file expect-rows src-count excluded-pairs
  local body="$1" expect="$2" srcs="$3" excl="$4" b n d bad=0
  for b in x86_64 aarch64 riscv64 wasm; do unset "RUN_$b" "EXIT_$b"; done
  CM_ROWS="$(body_rows "$body")"
  if [ "$CM_ROWS" != "$expect" ]; then
    echo "corpus manifest: the body holds $CM_ROWS rows, want $expect ($srcs × 4 − $excl)" >&2
    bad=2
  fi
  ## Two counts per backend, and both must be non-vacuous.
  ##   RUN_<b>  — sources that reached phase `run`. Zero means the backend never executed a program:
  ##              measured with a shimmed always-failing `aarch64-as`, `--write` blessed a baseline
  ##              holding ZERO aarch64 `run` rows and exited 0.
  ##   EXIT_<b> — DISTINCT exit codes among those rows. One means the runner answered the same thing
  ##              for every program, which is what a broken runner looks like from here: measured,
  ##              running wasmtime with an unwritable cache directory made all 1 235 wasm `run` rows
  ##              `exit 1`, a whole column that passed the RUN_ check while recording nothing.
  eval "$(awk -F'\t' '$3=="run" {c[$1]++; k[$1 FS $4]=1}
                       END{for (b in c) printf "RUN_%s=%d\n", b, c[b];
                           for (x in k) {split(x, a, FS); d[a[1]]++}
                           for (b in d) printf "EXIT_%s=%d\n", b, d[b]}' "$body")"
  for b in x86_64 aarch64 riscv64 wasm; do
    eval "n=\${RUN_$b:-0}; d=\${EXIT_$b:-0}"
    if [ "$n" -lt 1 ]; then
      echo "corpus manifest: backend $b reached phase 'run' for ZERO sources — it never executed a" >&2
      echo "  single program, so its rows record nothing about behaviour. Refusing to report a result." >&2
      bad=2
    elif [ "$d" -lt 2 ]; then
      echo "corpus manifest: backend $b ran $n programs and every one exited the SAME way — its runner" >&2
      echo "  is answering independently of the program, so the column is vacuous. Refusing to report." >&2
      bad=2
    fi
  done
  return "$bad"
}

## Compare two manifests. Returns 0 when identical. On a mismatch it says FIRST how many rows differ,
## then shows a bounded sample and states how many rows it withheld — the first cut printed
## `diff -u | head -80` with no count, so a 24-row change was reported as 15 rows with nothing saying
## that 9 were hidden. Sets DIFF_LINES.
DIFF_SHOW="${ALATYR_CORPUS_DIFF_SHOW:-60}"
compare_manifest() { # baseline candidate label
  local a="$1" b="$2" label="${3:-}" d
  DIFF_LINES=0
  cmp -s "$a" "$b" && return 0
  d="$WORK/manifest.diff"
  diff -u "$a" "$b" > "$d"
  local minus plus
  minus="$(grep -cE '^-[^-]' "$d" || true)"
  plus="$(grep -cE '^\+[^+]' "$d" || true)"
  DIFF_LINES=$((minus + plus))
  [ -z "$label" ] && return 1
  echo "$label: $DIFF_LINES differing lines ($minus only in the baseline, $plus only in the fresh run)" >&2
  ## Read it JOINED, not positionally. The raw diff is kept for the record, but a positional read
  ## pairs an added row with an unrelated removed one and invents transitions; and a bounded sample
  ## of it can withhold an entire severity class. `explain_manifest` bounds per class instead.
  explain_manifest "$a" "$b" >&2
  echo "  (the raw diff is $d)" >&2
  return 1
}

## The detector self-test: flip one row's exit field in a copy and require the comparison to report
## exactly that one row. A gate whose compare path is dead, or whose baseline is empty, passes
## everything; this is what makes "match" mean something.
selftest() { # manifest-file
  local src="$1" a="$WORK/selftest.a" b="$WORK/selftest.b" n
  n="$(body_rows "$src")"
  if [ "$n" -lt 1 ]; then
    echo "corpus manifest: detector self-test FAILED — $src holds no rows to compare" >&2
    return 1
  fi
  cp "$src" "$a"
  awk -F'\t' 'BEGIN{OFS="\t"} !done && NF==6 && $1 ~ /^(x86_64|aarch64|riscv64|wasm)$/ {$4=$4+1; done=1} {print}' "$a" > "$b"
  if cmp -s "$a" "$b"; then
    echo "corpus manifest: detector self-test FAILED — the planted row edit changed nothing" >&2
    return 1
  fi
  if compare_manifest "$a" "$b"; then
    echo "corpus manifest: detector self-test FAILED — the comparison called two different files equal" >&2
    return 1
  fi
  if [ "$DIFF_LINES" != 2 ]; then
    echo "corpus manifest: detector self-test FAILED — one flipped exit field reported $DIFF_LINES differing lines, want 2" >&2
    return 1
  fi
  echo "corpus manifest: detector self-test ok (one flipped exit field in $n rows is reported as a mismatch)"
  return 0
}

## The classifier's own gate-of-the-gate. A severity classifier nobody has seen misfile a row is
## decoration, and this one exists because the positional read it replaces once nearly let eight
## `run -> assemble/1` regressions land inside 23 wins. Plant one row of EACH class and require each
## to be reported under its own heading with the right count. Needs no compiler.
selftest_classes() { # manifest-file
  local src="$1" a="$WORK/cls.a" b="$WORK/cls.b" out="$WORK/cls.out" c want got
  awk -F'\t' 'NF==6 && $3=="run"{print; n++} n>=5{exit}' "$src" > "$a"
  if [ "$(grep -c '' "$a")" -lt 5 ]; then
    echo "corpus manifest: classifier self-test FAILED — fewer than 5 running rows to plant into" >&2
    return 1
  fi
  ## Rows 1 and 5 are the pair that matters most: both are `run -> not-run`, and only the one whose new
  ## phase ends in `_timeout` may be classified TIMED-OUT. If the new class ever widened to swallow the
  ## other, NO-LONGER-RUNS would drop to 0 here and this self-test would fail — which is the point.
  awk -F'\t' 'BEGIN{OFS="\t"}
    NR==1 { $3="assemble"; $4=1; print; next }              # -> NO-LONGER-RUNS
    NR==2 { $4=$4+1;       print; next }                    # -> EXIT-CHANGED
    NR==3 { $5="fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"; print; next }  # -> OUTPUT-CHANGED
    NR==4 { next }                                          # -> REMOVED
    NR==5 { $3="compile_timeout"; $4=124; print; next }      # -> TIMED-OUT
    {print}
    END { print "wasm\ttest/_classifier_selftest.al\trun\t42\t" \
                "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\t" \
                "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee" }  # -> ADDED
  ' "$a" > "$b"
  explain_manifest "$a" "$b" > "$out" 2>&1 || true
  for c in TIMED-OUT:1 NO-LONGER-RUNS:1 EXIT-CHANGED:1 OUTPUT-CHANGED:1 REMOVED:1 ADDED:1; do
    want="${c#*:}"; c="${c%%:*}"
    got="$(sed -n "s/^  ${c} *\([0-9][0-9]*\) pair(s).*/\1/p" "$out")"
    if [ "${got:-0}" != "$want" ]; then
      echo "corpus manifest: classifier self-test FAILED — class $c reported '${got:-absent}', want $want" >&2
      sed -n '1,40p' "$out" >&2
      return 1
    fi
  done
  ## A class must not swallow another: the planted NO-LONGER-RUNS row must not appear as EXIT-CHANGED.
  if [ "$(sed -n 's/^  NOW-RUNS *\([0-9][0-9]*\).*/\1/p' "$out")" != "" ]; then
    echo "corpus manifest: classifier self-test FAILED — a NOW-RUNS class appeared with nothing planted for it" >&2
    return 1
  fi
  echo "corpus manifest: classifier self-test ok (one planted row per class, each reported under its own heading)"
  return 0
}

## ---------------------------------------------------------------------------------------------------
## Serial re-observation of a timed-out source (issue #537).
##
## The production re-run of one source. Factored out under its own name so the self-test below can
## shadow it and drive the classification and accounting without a compiler — the same idiom the stream
## separation self-test uses for `timeout`.
reobserve_worker() { # id rel
  bash "$SELF" --worker "$(printf '%s\t%s' "$1" "$2")"
}

## The indices of every source that produced at least one `*_timeout` row, one per line, ascending.
timed_out_ids() { # rows-dir
  local d="$1"
  ## `find`, not a `"$d"/*` glob: an EMPTY rows directory would hand awk the literal pattern.
  find "$d" -maxdepth 1 -type f -exec awk -F'\t' '$3 ~ /_timeout$/ {print FILENAME}' {} + 2>/dev/null |
    sed 's|.*/||' | sort -u
}

loadavg_now() {
  if [ -r /proc/loadavg ]; then cut -d' ' -f1-3 /proc/loadavg; else printf 'unavailable'; fi
}

## Re-observe, ONE AT A TIME and with the parallel walk finished, every source that timed out, then
## classify on the second observation. Sets REOBS_SOURCES / REOBS_RECOVERED / REOBS_PERSISTED and
## prints one line per originally-timed-out row. Returns nonzero only when the mechanism itself broke.
##
## The whole SOURCE is re-observed, not just the timed-out pair: the worker's unit of work is one
## source's four backends and it writes that source's row file as a whole. A row of the same source that
## did NOT time out is therefore re-observed too — an equally valid fresh observation of the same
## compiler — and the exposure stays bounded to sources that timed out at all.
reobserve_timeouts() { # rows-dir jobfile
  local rowsdir="$1" jobfile="$2" ids id rel rc n=0 tstart verdict backend path before after
  REOBS_SOURCES=0; REOBS_RECOVERED=0; REOBS_PERSISTED=0
  ids="$(timed_out_ids "$rowsdir")"
  [ -n "$ids" ] || return 0
  REOBS_SOURCES="$(printf '%s\n' "$ids" | grep -c '')"
  mkdir -p "$WORK/rows-first" || return 1
  echo "corpus manifest: re-observation — $REOBS_SOURCES source(s) produced a '*_timeout' row in the parallel walk."
  echo "corpus manifest: re-observation   The ceiling catches a LOOPING compiler; it does not measure the machine's"
  echo "corpus manifest: re-observation   load. Each one is observed again ONE AT A TIME now that the walk is done,"
  echo "corpus manifest: re-observation   and the second observation is the one that gets classified."
  echo "corpus manifest: re-observation   (load average now: $(loadavg_now))"
  tstart=$SECONDS
  for id in $ids; do
    rel="$(awk -F'\t' -v want="$id" '$1==want{print $2; exit}' "$jobfile")"
    if [ -z "$rel" ]; then
      echo "corpus manifest: re-observation FAILED — no corpus source carries index $id" >&2
      return 1
    fi
    cp "$rowsdir/$id" "$WORK/rows-first/$id" || return 1
    n=$((n + 1))
    echo "corpus manifest: re-observation   [$n/$REOBS_SOURCES] $rel, serially…"
    reobserve_worker "$id" "$rel"; rc=$?
    if [ "$rc" != 0 ]; then
      echo "corpus manifest: re-observation FAILED — the serial worker for $rel exited $rc" >&2
      return 1
    fi
    if [ ! -s "$rowsdir/$id" ]; then
      echo "corpus manifest: re-observation FAILED — the serial worker for $rel produced no rows" >&2
      return 1
    fi
    ## Join the two observations of THIS source on (backend, path) and report only the rows whose first
    ## observation was a timeout. `< <(…)` and not a pipe: the counters must survive the loop.
    while IFS=$'\t' read -r verdict backend path before after; do
      printf 'corpus manifest: re-observation   %-8s %-52s %s -> %s   %s\n' \
        "$backend" "$path" "$before" "$after" "$verdict"
      case "$verdict" in
        RECOVERED) REOBS_RECOVERED=$((REOBS_RECOVERED + 1)) ;;
        *)         REOBS_PERSISTED=$((REOBS_PERSISTED + 1)) ;;
      esac
    done < <(awk -F'\t' 'BEGIN{OFS="\t"}
        FNR==NR { if (NF==6 && $3 ~ /_timeout$/) first[$1 SUBSEP $2] = $3 "/" $4; next }
        NF==6 && (($1 SUBSEP $2) in first) {
          print (($3 ~ /_timeout$/) ? "STILL-AT-THE-CEILING" : "RECOVERED"), \
                $1, $2, first[$1 SUBSEP $2], $3 "/" $4
        }' "$WORK/rows-first/$id" "$rowsdir/$id")
  done
  echo "corpus manifest: re-observation — $REOBS_RECOVERED row(s) recovered, $REOBS_PERSISTED still at the ceiling ($((SECONDS - tstart))s)"
  return 0
}

## The re-observation's own gate of the gate, in BOTH directions, with the worker stubbed so it needs no
## compiler and costs no ceiling. A mechanism that only ever un-fails a row is an eraser, not a
## measurement, so the genuine-hang direction is asserted first.
reobservation_selftest() {
  ## One name per `local`: bash expands ALL the words of a `local` command before it assigns any of
  ## them, so `local d=… rowsdir="$d/rows"` reads `$d` while `d` is already a fresh unset local, which
  ## under `set -u` aborts the script.
  local d="$WORK/reobs-selftest"
  local rowsdir="$d/rows"
  local jobfile="$d/jobs"
  local hash1=1111111111111111111111111111111111111111111111111111111111111111
  local hash2=2222222222222222222222222222222222222222222222222222222222222222
  rm -rf "$d"
  mkdir -p "$rowsdir" || return 1
  printf '%s\t%s\n' 000000 test/_reobs_selftest.al > "$jobfile"

  ## An empty rows directory and a walk with no timeout must both cost exactly nothing.
  (
    REOBS_SOURCES=unset
    reobserve_worker() { echo "corpus manifest: re-observation self-test FAILED — worker ran with no timeout row" >&2; return 1; }
    reobserve_timeouts "$rowsdir" "$jobfile" >/dev/null || exit 1
    [ "$REOBS_SOURCES" = 0 ] || { echo "corpus manifest: re-observation self-test FAILED — empty rows dir reported $REOBS_SOURCES source(s)" >&2; exit 1; }
    printf 'x86_64\ttest/_reobs_selftest.al\trun\t42\t%s\t%s\n' "$hash1" "$hash2" > "$rowsdir/000000"
    reobserve_timeouts "$rowsdir" "$jobfile" >/dev/null || exit 1
    [ "$REOBS_SOURCES" = 0 ] || { echo "corpus manifest: re-observation self-test FAILED — a walk with no timeout row re-observed $REOBS_SOURCES source(s)" >&2; exit 1; }
  ) || return 1

  ## Direction 1 — a GENUINE hang: the child breaches the ceiling on the serial re-run too. The row must
  ## stay a `*_timeout`, be counted as persisted, and NOT be counted as recovered.
  (
    printf 'x86_64\ttest/_reobs_selftest.al\tcompile_timeout\t124\t%s\t%s\n' "$hash1" "$hash2" > "$rowsdir/000000"
    reobserve_worker() {
      printf 'x86_64\ttest/_reobs_selftest.al\tcompile_timeout\t124\t%s\t%s\n' "$hash1" "$hash2" > "$rowsdir/$1"
    }
    reobserve_timeouts "$rowsdir" "$jobfile" > "$d/hang.out" || exit 1
    if [ "$REOBS_SOURCES" != 1 ] || [ "$REOBS_PERSISTED" != 1 ] || [ "$REOBS_RECOVERED" != 0 ]; then
      echo "corpus manifest: re-observation self-test FAILED — a child that times out TWICE was accounted" >&2
      echo "  sources=$REOBS_SOURCES persisted=$REOBS_PERSISTED recovered=$REOBS_RECOVERED, want 1/1/0" >&2
      exit 1
    fi
    if [ "$(awk -F'\t' '$3 ~ /_timeout$/ {n++} END{print n+0}' "$rowsdir/000000")" != 1 ]; then
      echo "corpus manifest: re-observation self-test FAILED — the re-run erased a genuine hang's timeout row" >&2
      exit 1
    fi
    grep -q 'STILL-AT-THE-CEILING' "$d/hang.out" || {
      echo "corpus manifest: re-observation self-test FAILED — a genuine hang was not reported" >&2; exit 1; }
  ) || return 1

  ## Direction 2 — STARVATION: the same child finishes inside the ceiling once nothing else is in
  ## flight. Its row must return to the phase the second observation saw, and be counted as recovered.
  (
    printf 'x86_64\ttest/_reobs_selftest.al\tcompile_timeout\t124\t%s\t%s\n' "$hash1" "$hash2" > "$rowsdir/000000"
    reobserve_worker() {
      printf 'x86_64\ttest/_reobs_selftest.al\trun\t42\t%s\t%s\n' "$hash1" "$hash2" > "$rowsdir/$1"
    }
    reobserve_timeouts "$rowsdir" "$jobfile" > "$d/starve.out" || exit 1
    if [ "$REOBS_SOURCES" != 1 ] || [ "$REOBS_RECOVERED" != 1 ] || [ "$REOBS_PERSISTED" != 0 ]; then
      echo "corpus manifest: re-observation self-test FAILED — a child that recovers when run alone was accounted" >&2
      echo "  sources=$REOBS_SOURCES recovered=$REOBS_RECOVERED persisted=$REOBS_PERSISTED, want 1/1/0" >&2
      exit 1
    fi
    if [ "$(awk -F'\t' '{print $3 "/" $4}' "$rowsdir/000000")" != "run/42" ]; then
      echo "corpus manifest: re-observation self-test FAILED — the recovered row is not the second observation" >&2
      exit 1
    fi
    grep -q 'RECOVERED' "$d/starve.out" || {
      echo "corpus manifest: re-observation self-test FAILED — a recovery was not reported" >&2; exit 1; }
  ) || return 1

  echo "corpus manifest: re-observation self-test ok (a twice-timing-out child stays a reported failure; one that finishes when run alone returns to its second observation)"
  return 0
}

rm -rf "$WORK"
mkdir -p "$WORK/rows" "$WORK/x86_64" "$WORK/aarch64" "$WORK/riscv64" "$WORK/wasm"
GENERATED="$WORK/corpus.manifest"
BODY="$WORK/body"

if [ -f "$MANIFEST" ]; then
  declared="$(sed -n 's/^row_count=//p' "$MANIFEST" | head -1)"
  actual="$(body_rows "$MANIFEST")"
  if [ "${declared:-x}" != "$actual" ]; then
    die "the committed baseline is internally inconsistent: row_count=${declared:-<absent>} but it holds $actual rows"
  fi
  selftest "$MANIFEST" || exit 2
  selftest_classes "$MANIFEST" || exit 2
elif [ "$MODE" = check ]; then
  echo "corpus manifest: the baseline is missing: $MANIFEST" >&2
  echo "  run scripts/corpus_manifest.sh --write after reviewing the generated rows" >&2
  exit 1
fi

# --- walk the corpus -------------------------------------------------------------------------------
esc() { printf '%s' "$1" | sed -e 's/[][\\.^$*+?(){}|]/\\&/g'; }
ROOT_RE="$(esc "$ROOT")"
HOME_RE="$(esc "${HOME:-/nonexistent-home}")"
WORK_RE="$(esc "$WORK")"
export ROOT ROOT_RE HOME_RE WORK WORK_RE CC TIMEOUT_SECS KEEP
if [ "$MODE" != selftest ]; then
  export A64_AS A64_LD QEMU_A64 RV64_AS RV64_LD QEMU_RV64 WAT2WASM WASMTIME
fi

## The offset normalizer is deliberately tested with both sides of its boundary. A real wasmtime
## backtrace must remain stable when only code offsets move; a guest's arbitrary stdout/stderr must
## remain different even when it prints the same frame-shaped text. This catches a sed pattern that
## recognizes the spelling but not the host context.
normalization_selftest() {
  local host_a="$WORK/normalize.host-a" host_b="$WORK/normalize.host-b"
  local guest_err_a="$WORK/normalize.guest-err-a" guest_err_b="$WORK/normalize.guest-err-b"
  local guest_out_a="$WORK/normalize.guest-out-a" guest_out_b="$WORK/normalize.guest-out-b"
  printf '%s\n' \
    'Error: failed to run main module <artifact>' \
    'Caused by:' \
    '    1: error while executing at wasm backtrace:' \
    '    0:    0x133 - <unknown>!<wasm function 6>' \
    '    1:    0x105 - <unknown>!<wasm function 7>' \
    '    2: wasm trap: wasm trap' > "$host_a"
  printf '%s\n' \
    'Error: failed to run main module <artifact>' \
    'Caused by:' \
    '    1: error while executing at wasm backtrace:' \
    '    0:    0x999 - <unknown>!<wasm function 6>' \
    '    1:    0x777 - <unknown>!<wasm function 7>' \
    '    2: wasm trap: wasm trap' > "$host_b"
  if [ "$(hash_stream "$host_a")" != "$(hash_stream "$host_b")" ]; then
    echo "corpus manifest: normalization self-test FAILED — host offsets still affect the hash" >&2
    return 1
  fi

  printf '%s\n' '    0:    0x133 - application diagnostic' > "$guest_err_a"
  printf '%s\n' '    0:    0x999 - application diagnostic' > "$guest_err_b"
  printf '%s\n' '    0:    0x133 - application diagnostic' > "$guest_out_a"
  printf '%s\n' '    0:    0x999 - application diagnostic' > "$guest_out_b"
  if [ "$(hash_stream "$guest_err_a")" = "$(hash_stream "$guest_err_b")" ] ||
     [ "$(hash_stream "$guest_out_a")" = "$(hash_stream "$guest_out_b")" ]; then
    echo "corpus manifest: normalization self-test FAILED — guest stream was masked" >&2
    return 1
  fi

  ## A guest is allowed to print text that is byte-for-byte indistinguishable from a runner diagnostic.
  ## The stream boundary, not content matching, is what identifies supervisor output. Keep two such guest
  ## messages different so a future normalizer cannot silently erase an application-owned signal report.
  printf '%s\n' 'qemu-aarch64: uncaught target signal 5 (Trace/breakpoint trap) - core dumped' > "$guest_err_a"
  printf '%s\n' 'qemu-aarch64: uncaught target signal 6 (Aborted) - core dumped' > "$guest_err_b"
  if [ "$(hash_stream "$guest_err_a")" = "$(hash_stream "$guest_err_b")" ]; then
    echo "corpus manifest: normalization self-test FAILED — runner-looking guest diagnostics were masked" >&2
    return 1
  fi
  echo "corpus manifest: normalization self-test ok (host offsets muted; guest stdout/stderr preserved)"
}
normalization_selftest || exit 2

## Prove the stream boundary without relying on a host's coredump policy. The fake supervisor emits the
## exact class of text that GNU timeout writes after a signal; the guest emits its own stderr and exits
## with a signal-shaped status. The old combined-redirection implementation puts both lines in the
## hashed file, while the wrapper above leaves only the guest line there. The second probe uses the real
## timeout for a 124 status, and the third keeps step's existing <phase>_timeout mapping alive.
stream_separation_selftest() {
  local d="$WORK/stream-selftest" supervisor_line='timeout: the monitored command dumped core'
  local hash_a hash_b expected_hash sleep_bin rc_a rc_b rc
  rm -rf "$d"
  mkdir -p "$d"
  sleep_bin="$(command -v sleep)"

  (
    timeout() {
      shift
      printf '%s\n' 'timeout: the monitored command dumped core' >&2
      "$@"
    }
    run_prog "$d/a.out" "$d/a.err" /bin/sh -c 'printf "%s\n" "guest-child-diagnostic" >&2; printf "%s\n" "guest-stdout"; exit 133'
    rc_a=$?
    run_prog "$d/b.out" "$d/b.err" /bin/sh -c 'printf "%s\n" "guest-child-diagnostic" >&2; printf "%s\n" "guest-stdout"; exit 133'
    rc_b=$?
    printf '%s\n' 'guest-child-diagnostic' >"$d/expected.err"
    printf '%s\n' 'guest-stdout' >"$d/expected.out"
    printf '%s\n' "$supervisor_line" >"$d/expected.timeout"
    if [ "$rc_a" != 133 ] || [ "$rc_b" != 133 ]; then
      echo "corpus manifest: stream separation self-test FAILED — child status changed ($rc_a/$rc_b, want 133)" >&2
      exit 1
    fi
    if ! cmp -s "$d/a.err" "$d/expected.err" || ! cmp -s "$d/b.err" "$d/expected.err"; then
      echo "corpus manifest: stream separation self-test FAILED — child stderr was mixed or masked" >&2
      exit 1
    fi
    if ! cmp -s "$d/a.out" "$d/expected.out" || ! cmp -s "$d/b.out" "$d/expected.out"; then
      echo "corpus manifest: stream separation self-test FAILED — child stdout changed" >&2
      exit 1
    fi
    if ! cmp -s "$d/a.err.timeout" "$d/expected.timeout" || ! cmp -s "$d/b.err.timeout" "$d/expected.timeout"; then
      echo "corpus manifest: stream separation self-test FAILED — supervisor stderr was not separated" >&2
      exit 1
    fi
    hash_a="$(hash_stream "$d/a.err")"
    hash_b="$(hash_stream "$d/b.err")"
    expected_hash="$(hash_stream "$d/expected.err")"
    if [ "$hash_a" != "$hash_b" ] || [ "$hash_a" != "$expected_hash" ]; then
      echo "corpus manifest: stream separation self-test FAILED — child hash was not stable ($hash_a/$hash_b/$expected_hash)" >&2
      exit 1
    fi
  ) || return 1

  (
    TIMEOUT_SECS=1
    run_prog "$d/run-timeout.out" "$d/run-timeout.err" /bin/sh -c 'printf "%s\n" "guest-before-timeout" >&2; "$1" 2' corpus-stream-timeout "$sleep_bin"
    rc=$?
    if [ "$rc" != 124 ]; then
      echo "corpus manifest: stream separation self-test FAILED — run timeout status changed ($rc, want 124)" >&2
      exit 1
    fi
    printf '%s\n' 'guest-before-timeout' >"$d/expected-run-timeout.err"
    if ! cmp -s "$d/run-timeout.err" "$d/expected-run-timeout.err"; then
      echo "corpus manifest: stream separation self-test FAILED — timed-out child stderr changed" >&2
      exit 1
    fi
  ) || return 1

  (
    timeout() { shift; return 124; }
    PHASE=unset
    step compile "$d/step-timeout.out" "$d/step-timeout.err" /bin/true
    rc=$?
    if [ "$rc" != 124 ] || [ "$PHASE" != compile_timeout ]; then
      echo "corpus manifest: stream separation self-test FAILED — timeout phase/status changed (rc=$rc, phase=$PHASE)" >&2
      exit 1
    fi
  ) || return 1

  echo "corpus manifest: stream separation self-test ok (child hash stable, supervisor stderr separate, run rc=124, compile_timeout preserved)"
  return 0
}
stream_separation_selftest || exit 2
reobservation_selftest || exit 2

## The corpus's own source tree has one particular compiler layout. A manifest can therefore remain
## green while a compiler change breaks a second layout that no tracked fixture reaches. Exercise that
## seam with two generated, valid programs: the same basic function once with no dead locals and once
## with N unused mutable u64 bindings. The compiler must compile and run both, their observable streams
## must agree, and the emitted function prologue must show a genuinely different stack frame. This is a
## layout observation, not a symbol-presence check; if dead bindings stop perturbing the frame, the gate
## fails loudly instead of becoming vacuous.
frame_bytes() { # gas-file function-label -> one numeric stack allocation
  local gas="$1" fn="$2"
  awk -v fn="$fn" '
    $0 == fn ":" { inside=1; next }
    inside && /^[^[:space:]].*:[[:space:]]*$/ { exit }
    inside && /subq[[:space:]]+\$[0-9]+,[[:space:]]+%rsp/ {
      line=$0
      sub(/.*\$/, "", line)
      sub(/,.*/, "", line)
      print line
      found++
    }
    END { if (!inside || found != 1) exit 1 }
  ' "$gas"
}

write_frame_probe() { # source-file dead-mut-count
  local src="$1" n="$2" i=0
  {
    printf '%s\n' 'main := fn() -> u64 {'
    while [ "$i" -lt "$n" ]; do
      printf '  mut dead_%s : u64 = 0\n' "$i"
      i=$((i + 1))
    done
    printf '%s\n' '  return 42' '}'
  } > "$src"
}

frame_perturbation_selftest() {
  local d="$WORK/frame-selftest" n=8
  local base_src="$d/frame_base.al" dead_src="$d/frame_dead.al"
  local base_gas="$d/frame_base.s" dead_gas="$d/frame_dead.s"
  local base_fn=frame_base__main dead_fn=frame_dead__main
  local base_frame dead_frame delta base_rc dead_rc rc

  rm -rf "$d"
  mkdir -p "$d"
  write_frame_probe "$base_src" 0
  write_frame_probe "$dead_src" "$n"

  if step compile "$d/frame_base.compile.out" "$d/frame_base.compile.err" "$CC" "$base_src"; then
    :
  else
    rc=$?
    echo "corpus manifest: frame perturbation self-test FAILED — base source did not compile (rc=$rc, phase=$PHASE)" >&2
    sed 's/^/  | /' "$d/frame_base.compile.err" >&2
    return 1
  fi
  if step compile "$d/frame_dead.compile.out" "$d/frame_dead.compile.err" "$CC" "$dead_src"; then
    :
  else
    rc=$?
    echo "corpus manifest: frame perturbation self-test FAILED — N=$n source did not compile (rc=$rc, phase=$PHASE)" >&2
    sed 's/^/  | /' "$d/frame_dead.compile.err" >&2
    return 1
  fi
  mv "$d/frame_base.compile.out" "$base_gas"
  mv "$d/frame_dead.compile.out" "$dead_gas"

  base_frame="$(frame_bytes "$base_gas" "$base_fn")" || {
    echo "corpus manifest: frame perturbation self-test FAILED — no unique frame allocation for $base_fn" >&2
    return 1
  }
  dead_frame="$(frame_bytes "$dead_gas" "$dead_fn")" || {
    echo "corpus manifest: frame perturbation self-test FAILED — no unique frame allocation for $dead_fn" >&2
    return 1
  }
  case "$base_frame:$dead_frame" in
    ''|*[!0-9:]*)
      echo "corpus manifest: frame perturbation self-test FAILED — non-numeric frame sizes '$base_frame' '$dead_frame'" >&2
      return 1
      ;;
  esac
  if [ "$dead_frame" -le "$base_frame" ]; then
    echo "corpus manifest: frame perturbation self-test FAILED — N=$n dead muts did not increase the frame ($base_frame -> $dead_frame)" >&2
    return 1
  fi
  delta=$((dead_frame - base_frame))
  if cmp -s "$base_gas" "$dead_gas"; then
    echo "corpus manifest: frame perturbation self-test FAILED — generated layouts are byte-identical" >&2
    return 1
  fi

  if step compile "$d/frame_base.build.out" "$d/frame_base.build.err" "$CC" -o "$d/frame_base.bin" "$base_src" &&
     [ -x "$d/frame_base.bin" ]; then
    :
  else
    rc=$?
    echo "corpus manifest: frame perturbation self-test FAILED — base executable did not build (rc=$rc, phase=${PHASE:-compile})" >&2
    sed 's/^/  | /' "$d/frame_base.build.err" >&2
    return 1
  fi
  if step compile "$d/frame_dead.build.out" "$d/frame_dead.build.err" "$CC" -o "$d/frame_dead.bin" "$dead_src" &&
     [ -x "$d/frame_dead.bin" ]; then
    :
  else
    rc=$?
    echo "corpus manifest: frame perturbation self-test FAILED — N=$n executable did not build (rc=$rc, phase=${PHASE:-compile})" >&2
    sed 's/^/  | /' "$d/frame_dead.build.err" >&2
    return 1
  fi

  base_rc=0
  run_prog "$d/frame_base.run.out" "$d/frame_base.run.err" "./$d/frame_base.bin" || base_rc=$?
  dead_rc=0
  run_prog "$d/frame_dead.run.out" "$d/frame_dead.run.err" "./$d/frame_dead.bin" || dead_rc=$?
  if [ "$base_rc" != 42 ] || [ "$dead_rc" != 42 ]; then
    echo "corpus manifest: frame perturbation self-test FAILED — result changed (base rc=$base_rc, N=$n rc=$dead_rc, want 42)" >&2
    return 1
  fi
  if ! cmp -s "$d/frame_base.run.out" "$d/frame_dead.run.out" ||
     ! cmp -s "$d/frame_base.run.err" "$d/frame_dead.run.err"; then
    echo "corpus manifest: frame perturbation self-test FAILED — generated programs changed stdout/stderr" >&2
    return 1
  fi
  echo "corpus manifest: frame perturbation self-test ok (N=$n dead muts, frame $base_frame -> $dead_frame, delta=$delta, both run=42)"
  return 0
}
## The body-shape self-test: drive `check_body_shape` — this stage's row-count and non-vacuity
## decider — with planted bodies, in every direction it can refuse and in the direction it must
## accept. Costs no child and no walk. In a SUBSHELL and read from FILES for the reason #599
## recorded: an unbound variable or an arithmetic error inside a driven function unwinds to top
## level and ENDS THE SCRIPT, so a diagnostic written for that case can never print.
CM_BODY_SELFTEST_EXPECTED=19
body_shape_selftest() { # work-dir
  local st="$1" bad="" k=0 out rc
  rm -rf "$st"; mkdir -p "$st" || return 1
  _ck() { k=$((k+1)); [ "$1" = 0 ] || bad="$bad $2"; }
  ## Four sources × four backends = 16 rows, each backend running all four and answering
  ## differently. Four, not two, so that a check can corrupt ONE source's rows on every backend
  ## and still leave each backend three running rows with three distinct exits — otherwise the
  ## structural checks below would be measuring the non-vacuity half instead of the row count.
  _body() { # file -- seeds the clean sixteen
    awk 'BEGIN { OFS = "\t"
      split("x86_64 aarch64 riscv64 wasm", b, " ")
      split("42 7 9 13", e, " ")
      split("a b c d", f, " ")
      for (i = 1; i <= 4; i++) for (j = 1; j <= 4; j++)
        print b[i], "test/" f[j] ".al", "run", e[j], "h" j, "H" j }' > "$1"
  }
  _body "$st/clean"

  # 1 · a complete, non-vacuous body is accepted, and the row count it reports is the one it counted.
  check_body_shape "$st/clean" 16 4 0 2>"$st/e1"; rc=$?
  [ "$rc" = 0 ]; _ck $? "body-shape-refused-a-complete-body(rc=$rc: $(cat "$st/e1"))"
  [ "$CM_ROWS" = 16 ]; _ck $? "body-shape-miscounted-a-complete-body(CM_ROWS=$CM_ROWS)"
  [ "${RUN_x86_64:-0}" = 4 ] && [ "${EXIT_wasm:-0}" = 4 ]
  _ck $? "body-shape-did-not-publish-the-per-backend-counters(run=${RUN_x86_64:-0} exits=${EXIT_wasm:-0})"

  # 2 · THE TRUNCATED WALK — the measured defect. One whole source is missing from a body that is
  #     otherwise perfect: every backend still ran, each with three distinct exits, so all four
  #     non-vacuity counters are happy and only the row count can see the loss. That is exactly
  #     the shape the parent measurement had at scale — 100 of 2052 sources walked, 400 rows
  #     blessed as an oracle, exit 0.
  awk -F'\t' '$2 != "test/d.al"' "$st/clean" > "$st/short"
  out="$(check_body_shape "$st/short" 16 4 0 2>&1)"; rc=$?
  [ "$rc" = 2 ]; _ck $? "body-shape-accepted-a-truncated-body(rc=$rc)"
  case "$out" in *'holds 12 rows, want 16'*) _ck 0 x ;;
                 *) _ck 1 "body-shape-did-not-say-how-short-the-body-is($out)" ;; esac
  case "$out" in *'4 × 4 − 0'*) _ck 0 x ;;
                 *) _ck 1 body-shape-did-not-show-how-the-expectation-is-derived ;; esac

  # 3 · …and the other direction: the count is an IDENTITY, not a floor. A duplicated row is not a
  #     manifest either, and a `-lt` comparison would wave it through.
  { cat "$st/clean"; head -1 "$st/clean"; } > "$st/long"
  check_body_shape "$st/long" 16 4 0 2>/dev/null
  [ $? = 2 ]; _ck $? body-shape-accepted-a-body-with-more-rows-than-the-corpus-owes

  # 4 · STRUCTURE, not lines, and this is the half `wc -l` cannot do. Both planted bodies hold
  #     exactly the sixteen LINES the walk's own per-source check counts, and each still leaves
  #     every backend three running rows with three distinct exits, so the non-vacuity half is
  #     satisfied too: the row count is the only thing left that can see them.
  awk -F'\t' 'BEGIN { OFS = "\t" } $2 == "test/d.al" { print $1, $2, $3; next } { print }' \
    "$st/clean" > "$st/ragged"
  [ "$(grep -c '' < "$st/ragged")" = 16 ]; _ck $? selftest-planted-a-ragged-body-of-the-wrong-length
  out="$(check_body_shape "$st/ragged" 16 4 0 2>&1)"; rc=$?
  [ "$rc" = 2 ]; _ck $? "body-shape-counted-a-three-field-line-as-a-row(rc=$rc)"
  case "$out" in *'holds 12 rows, want 16'*) _ck 0 x ;;
                 *) _ck 1 "body-shape-did-not-count-structurally($out)" ;; esac
  awk -F'\t' 'BEGIN { OFS = "\t" } $2 == "test/d.al" { $1 = "sparc" } { print }' \
    "$st/clean" > "$st/alien"
  [ "$(grep -c '' < "$st/alien")" = 16 ]; _ck $? selftest-planted-an-alien-body-of-the-wrong-length
  check_body_shape "$st/alien" 16 4 0 2>/dev/null
  [ $? = 2 ]; _ck $? body-shape-counted-rows-of-an-unknown-backend

  # 5 · a backend that never executed a program. Measured with a shimmed always-failing
  #     `aarch64-as`: `--write` blessed a baseline holding ZERO aarch64 `run` rows.
  awk -F'\t' 'BEGIN { OFS = "\t" } $1 == "aarch64" { $3 = "assemble"; $4 = 1 } { print }' \
    "$st/clean" > "$st/norun"
  out="$(check_body_shape "$st/norun" 16 4 0 2>&1)"; rc=$?
  [ "$rc" = 2 ]; _ck $? "body-shape-accepted-a-backend-that-ran-nothing(rc=$rc)"
  case "$out" in *"backend aarch64 reached phase 'run' for ZERO sources"*) _ck 0 x ;;
                 *) _ck 1 "body-shape-did-not-name-the-backend-that-ran-nothing($out)" ;; esac

  # 6 · a backend whose runner answers the same thing for every program.
  awk -F'\t' 'BEGIN { OFS = "\t" } $1 == "wasm" { $4 = 1 } { print }' "$st/clean" > "$st/uniform"
  out="$(check_body_shape "$st/uniform" 16 4 0 2>&1)"; rc=$?
  [ "$rc" = 2 ]; _ck $? "body-shape-accepted-a-runner-answering-independently-of-the-program(rc=$rc)"
  case "$out" in *'backend wasm ran 4 programs and every one exited the SAME way'*) _ck 0 x ;;
                 *) _ck 1 "body-shape-did-not-name-the-vacuous-column($out)" ;; esac

  # 7 · the eraser control, and the stale-counter control with it. A decider that refused every
  #     body would satisfy 2 to 6 and block every run; and the counters must describe THIS body,
  #     not the last one — check 6 left `EXIT_wasm=1` behind.
  check_body_shape "$st/clean" 16 4 0 2>/dev/null
  [ $? = 0 ]; _ck $? body-shape-refused-a-clean-body-after-refusing-a-broken-one
  [ "${EXIT_wasm:-0}" = 4 ]; _ck $? "body-shape-kept-a-stale-counter-from-the-previous-body(EXIT_wasm=${EXIT_wasm:-0})"
  ## Quarantined pairs are part of the expectation, so a body short by exactly the excluded pairs
  ## is the CORRECT one. The exclusion list is empty today; if it stops being, this is the check
  ## that keeps the arithmetic honest rather than the comment above it.
  grep -v "^wasm	test/a.al	" "$st/clean" > "$st/quarantined"
  check_body_shape "$st/quarantined" 15 4 1 2>/dev/null
  [ $? = 0 ]; _ck $? body-shape-refused-a-body-whose-only-missing-rows-are-quarantined

  printf '%s' "$bad" > "$st/bad"; printf '%s' "$k" > "$st/checks"; : > "$st/complete"
  unset -f _ck _body
  if [ -n "$bad" ]; then echo "corpus manifest: body-shape self-test FAILED —$bad" >&2; return 1; fi
  if [ "$k" -lt "$CM_BODY_SELFTEST_EXPECTED" ]; then
    echo "corpus manifest: body-shape self-test FAILED — ran $k checks, expected at least" >&2
    echo "  $CM_BODY_SELFTEST_EXPECTED; a self-test that reports fewer checks than it owes is a failure" >&2
    return 1
  fi
  echo "corpus manifest: body-shape self-test ok ($k checks — a truncated body, an overlong one,"
  echo "  ragged and alien rows that hold the right LINE count, a backend that ran nothing, a runner"
  echo "  answering the same thing for every program, and the clean and quarantined bodies it must accept)"
  return 0
}
CM_BST="$WORK/body-shape-selftest"
( body_shape_selftest "$CM_BST" ); CM_BST_RC=$?
if [ ! -f "$CM_BST/complete" ]; then
  echo "corpus manifest: the body-shape self-test did NOT run to completion (rc=$CM_BST_RC) — it" >&2
  echo "  recorded no verdict, so this run proves nothing about the row-count or non-vacuity decision" >&2
  exit 2
fi
[ -s "$CM_BST/bad" ] && { echo "corpus manifest: body-shape self-test recorded failures — $(cat "$CM_BST/bad")" >&2; exit 2; }
[ "$(cat "$CM_BST/checks")" -ge "$CM_BODY_SELFTEST_EXPECTED" ] || {
  echo "corpus manifest: body-shape self-test recorded $(cat "$CM_BST/checks") checks, expected at least $CM_BODY_SELFTEST_EXPECTED" >&2; exit 2; }
[ "$CM_BST_RC" = 0 ] || exit 2
## Planted self-test for wasm's phase fidelity (#683's oracle half): the three terminal facts a wasm
## program can end on must not collapse into one word. Each is planted as the stderr a real wasmtime
## produces, measured against the wording quoted in `wasm_link_failed`'s comment.
wasm_phase_selftest() {
  local d rc=0
  d="$(mktemp -d "${TMPDIR:-/tmp}/corpus-wasm-phase.XXXXXX")" || return 2
  printf '%s\n' "Error: failed to run main module \`prog.wasm\`" "" "Caused by:" \
    '    0: failed to instantiate "prog.wasm"' \
    '    1: unknown import: `env::shared_impl` has not been defined' > "$d/instantiate.err"
  printf '%s\n' "Error: failed to run main module \`prog.wasm\`" "" "Caused by:" \
    "    0: wasm trap: unreachable" > "$d/trap.err"
  : > "$d/ran.err"
  wasm_link_failed "$d/instantiate.err"; rc=$?
  [ "$rc" = 0 ] || { echo "corpus manifest: wasm-phase self-test FAILED — an unresolved @extern import was NOT recognised as a link failure, so it would be recorded as a run that never happened" >&2; rm -rf "$d"; return 1; }
  wasm_link_failed "$d/trap.err"; rc=$?
  [ "$rc" != 0 ] || { echo "corpus manifest: wasm-phase self-test FAILED — a program that TRAPPED (exit 134) would be refiled as a link failure, hiding a real run" >&2; rm -rf "$d"; return 1; }
  wasm_link_failed "$d/ran.err"; rc=$?
  [ "$rc" != 0 ] || { echo "corpus manifest: wasm-phase self-test FAILED — a program that ran and returned 1 would be refiled as a link failure" >&2; rm -rf "$d"; return 1; }
  rm -rf "$d"
  echo "corpus manifest: wasm-phase self-test ok (an uninstantiated module is recorded as link; a trap and a real exit-1 run stay run)"
  return 0
}
## Planted self-test for the same-exit / earlier-phase distinction (#683). The two facts look identical in
## the phase column and mean opposite things, so both are planted: a `run/1 -> link/1` pair, which is what
## an uninstantiated wasm module always was and must NOT be called a regression, and a `run/42 -> link/1`
## pair, which is a program that had a value to lose and MUST be called one.
phase_relabel_selftest() {
  local d out got rc=0 E
  ## The sha256 of an empty stream, spelled here because `SHA_EMPTY` belongs to xbackend_diff.sh and
  ## this script does not source it — an undefined name would have planted rows with empty hash columns,
  ## which is a malformed row rather than a row with no output.
  E="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  d="$(mktemp -d "${TMPDIR:-/tmp}/corpus-phase-relabel.XXXXXX")" || return 2
  printf 'wasm\tp/a.al\trun\t1\t%s\t%s\nwasm\tp/b.al\trun\t42\t%s\t%s\n' \
    "$E" "$E" "$E" "$E" > "$d/old"
  printf 'wasm\tp/a.al\tlink\t1\t%s\t%s\nwasm\tp/b.al\tlink\t1\t%s\t%s\n' \
    "$E" "$E" "$E" "$E" > "$d/new"
  out="$(explain_manifest "$d/old" "$d/new" 2>&1)"
  got="$(printf '%s\n' "$out" | sed -n 's/^  PHASE-CHANGED *\([0-9][0-9]*\) pair(s).*/\1/p' | head -1)"
  [ "${got:-0}" = "1" ] || { echo "corpus manifest: phase-relabel self-test FAILED — a same-exit run/1 -> link/1 was not PHASE-CHANGED (got '${got:-absent}', want 1)"; printf '%s\n' "$out" | head -20; rc=1; }
  got="$(printf '%s\n' "$out" | sed -n 's/^  NO-LONGER-RUNS *\([0-9][0-9]*\) pair(s).*/\1/p' | head -1)"
  [ "${got:-0}" = "1" ] || { echo "corpus manifest: phase-relabel self-test FAILED — a run/42 -> link/1 (a value lost) was not NO-LONGER-RUNS (got '${got:-absent}', want 1)"; printf '%s\n' "$out" | head -20; rc=1; }
  rm -rf "$d"
  [ "$rc" = 0 ] && echo "corpus manifest: phase-relabel self-test ok (same-exit run->link is a correction; losing a value is still a REGRESSION)"
  return $rc
}
phase_relabel_selftest || exit 2
wasm_phase_selftest || exit 2
run_delta_selftest || exit 2

frame_perturbation_selftest || exit 2
if [ "$MODE" = selftest ]; then
  echo "corpus manifest: self-tests only; committed corpus.manifest untouched"
  exit 0
fi

JOBFILE="$WORK/jobs"
: > "$JOBFILE"
i=0
for rel in "${SOURCES[@]}"; do
  printf '%06d\t%s\n' "$i" "$rel" >> "$JOBFILE"
  i=$((i + 1))
done

echo "corpus manifest: walking the corpus (timeout ${TIMEOUT_SECS}s per child, $JOBS in flight)…"
start=$SECONDS
xargs -a "$JOBFILE" -d '\n' -P "$JOBS" -I{} bash "$SELF" --worker {} &
xpid=$!
tick=0
while kill -0 "$xpid" 2>/dev/null; do
  sleep 5
  tick=$((tick + 1))
  kill -0 "$xpid" 2>/dev/null || break
  if [ "$((tick % 6))" = 0 ]; then
    echo "corpus manifest:   $(ls "$WORK/rows" | wc -l)/$SRC_COUNT sources observed ($((SECONDS - start))s)"
  fi
done
wait "$xpid"; xrc=$?
elapsed=$((SECONDS - start))
[ "$xrc" = 0 ] || die "a corpus worker failed (xargs exit $xrc) — the manifest is incomplete"

# --- re-observe the timed-out sources SERIALLY, before anything is classified (issue #537) ----------
## Cost when nothing timed out: `timed_out_ids` over the row files, and nothing else. Cost when one
## source timed out: that one source's four backends, once, with nothing else of this gate's in flight.
REOBS_SOURCES=0; REOBS_RECOVERED=0; REOBS_PERSISTED=0
if [ "$REOBSERVE" = 0 ]; then
  if [ -n "$(timed_out_ids "$WORK/rows")" ]; then
    echo "corpus manifest: ALATYR_CORPUS_REOBSERVE=0 — a '*_timeout' row is being classified from ONE" >&2
    echo "  observation taken under the parallel walk's own load. That is the pre-#537 behaviour and it" >&2
    echo "  cannot distinguish a hang from starvation; the verdict below is not a gate verdict." >&2
  fi
else
  reobserve_timeouts "$WORK/rows" "$JOBFILE" || die "the serial re-observation of a timed-out source failed"
fi

# --- assemble the body, asserting per source that its rows exist ------------------------------------
: > "$BODY"
fail=0
while IFS=$'\t' read -r id rel; do
  f="$WORK/rows/$id"
  want=$((4 - $(excluded_for_source "$rel")))
  if [ ! -f "$f" ]; then
    echo "corpus manifest: NO ROWS for $rel — the worker produced nothing" >&2; fail=1; continue
  fi
  got="$(wc -l < "$f")"
  if [ "$got" != "$want" ]; then
    echo "corpus manifest: $rel produced $got rows, want $want" >&2; fail=1
  fi
  cat "$f" >> "$BODY"
done < "$JOBFILE"
[ "$fail" = 0 ] || die "the corpus walk is incomplete; the rows below are NOT a full manifest"

# --- the gate of the gate: non-vacuity, counted from the BODY ---------------------------------------
check_body_shape "$BODY" "$EXPECT_ROWS" "$SRC_COUNT" "$EXCLUDED_PAIRS" || exit 2
ROWS="$CM_ROWS"
## A `*_timeout` row is the one observation that can move because the MACHINE was busy rather than
## because the compiler changed, so it is never silent. What is reported now is the SECOND observation:
## a row that reaches here breached the ceiling in the parallel walk AND again on its own, so the stage
## is willing to stand behind it — which is the difference between reporting a measurement and
## reporting the absence of one.
TIMEOUTS="$(awk -F'\t' '$3 ~ /_timeout$/ {n++} END{print n+0}' "$BODY")"
if [ "$TIMEOUTS" != 0 ]; then
  echo "corpus manifest: WARNING — $TIMEOUTS row(s) are recorded as a '*_timeout' phase." >&2
  if [ "$REOBSERVE" = 0 ]; then
    echo "  The serial re-observation was switched off (ALATYR_CORPUS_REOBSERVE=0), so this is ONE" >&2
    echo "  observation taken under the walk's own load and it cannot tell a hang from starvation." >&2
  else
    echo "  Each one breached the ${TIMEOUT_SECS}s ceiling in the parallel walk AND again on a serial" >&2
    echo "  re-observation with nothing else of this gate's in flight. Two independent observations is" >&2
    echo "  what this stage is willing to report, so the rows stand: either the compiler loops on that" >&2
    echo "  input, or the machine was loaded from OUTSIDE this gate for the whole run. They are" >&2
    echo "  classified TIMED-OUT, never NO-LONGER-RUNS." >&2
  fi
  echo "  Do NOT regenerate the oracle to absorb one: its committed value is the correct one, and" >&2
  echo "  absorbing a timeout row would freeze a contention artifact into the baseline. Re-run this" >&2
  echo "  stage alone on a quiet machine and report the re-measurement." >&2
elif [ "$REOBS_RECOVERED" != 0 ]; then
  echo "corpus manifest: re-observation — $REOBS_RECOVERED row(s) hit the ${TIMEOUT_SECS}s ceiling under the parallel" \
       "walk and finished inside it when re-observed alone; the manifest holds no '*_timeout' row."
fi
echo "corpus manifest: rows=$ROWS  phase run / distinct exits:" \
     "x86_64=${RUN_x86_64:-0}/${EXIT_x86_64:-0}" "aarch64=${RUN_aarch64:-0}/${EXIT_aarch64:-0}" \
     "riscv64=${RUN_riscv64:-0}/${EXIT_riscv64:-0}" "wasm=${RUN_wasm:-0}/${EXIT_wasm:-0}" "(${elapsed}s)"

# --- the oracle's scope (#1126 S3) -----------------------------------------------------------------
## Where a fixture states its expectation (`## expect:`, scripts/fixture_oracle.sh), the verdict on its
## (phase, exit) is that directive, or a row of scripts/known-deviations.tsv, against THIS walk
## (scripts/fixture_expect.sh --gate --observed). Recording the same pairs here as well would make every
## behaviour fix an oracle change again, which is what #1126 removes. So the committed manifest holds:
##   • every pair of a source with NO directive — the observation oracle, until each one is stated
##     (the S1 review list: `scripts/fixture_expect.sh --review`); it only shrinks, because
##     fixture_expect.sh fails a fixture that has neither a directive nor rows here (a new fixture
##     states its expectation);
##   • every pair of a directive source that writes to stdout on some backend — the OUTPUT SIDECAR. A
##     directive states phase and exit, not the bytes printed, and 39 directive sources print on some
##     backend (14 twin rows exit as stated with other bytes; measured on the manifest of 2cf60b45). Their
##     rows stay whole until the directive grammar can state the output.
## "Has a directive" is EXPECT_TRIGGER, the one pattern every reader of that question uses. The walk
## itself is unchanged and is kept whole at $OBSERVED: the gate's readers of "what each backend did"
## (fixture_expect.sh, the xbackend ratchet) read that file, never the committed scope.
## shellcheck source=fixture_oracle.sh
. "$ROOT/scripts/fixture_oracle.sh"
OBSERVED="$WORK/observed.manifest"
SHA_EMPTY_STREAM=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
printf '%s\0' "${SOURCES[@]}" | xargs -0 grep -liE -- "$EXPECT_TRIGGER" | sort > "$WORK/directed"
## three passes over two files: awk tells inputs apart by FILENAME, so the body's two passes are counted
awk -F'\t' -v E="$SHA_EMPTY_STREAM" '
  FNR == 1 { pass++ }
  pass == 1 { D[$1] = 1; next }
  pass == 2 { if (($2 in D) && $5 != E) P[$2] = 1; next }
  !($2 in D) || ($2 in P)' "$WORK/directed" "$BODY" "$BODY" > "$WORK/scoped"
SCOPED_ROWS="$(grep -c '' < "$WORK/scoped")"
SCOPED_SRC="$(cut -f2 "$WORK/scoped" | sort -u | grep -c '')"
DIRECTED_N="$(grep -c '' < "$WORK/directed")"
SIDECAR_SRC="$(awk -F'\t' 'FILENAME == ARGV[1] { D[$1] = 1; next } ($2 in D) { print $2 }' "$WORK/directed" "$WORK/scoped" | sort -u | grep -c '')"
echo "corpus manifest: scope — the committed oracle holds $SCOPED_SRC of $SRC_COUNT sources ($SCOPED_ROWS rows):" \
     "$((SCOPED_SRC - SIDECAR_SRC)) with no directive, $SIDECAR_SRC directive sources that print (the output sidecar);" \
     "the other $((DIRECTED_N - SIDECAR_SRC)) directive sources are judged by fixture_expect.sh against $OBSERVED"

write_manifest() { # scope-line source-count row-count body
  printf '# Alatyr per-file corpus manifest; generated by scripts/corpus_manifest.sh\n'
  printf '# Paths in a row are relative to this checkout; captured streams are normalized before\n'
  printf '# hashing, so the file is reproducible in a checkout at a DIFFERENT path.\n'
  printf 'format=alatyr-corpus-manifest-v2\n'
  ## Read this as the GIT PATHSPEC it is, not as a shell glob: git's `*` matches `/`, so the one
  ## pattern also selects the multi-file package fixtures under test/package/**. That is why
  ## source_count is ~1663 and not the ~1352 files a shell `ls test/*.al` would show. The literal is
  ## part of the compared file, so changing its wording costs a full oracle regeneration.
  printf 'source_glob=test/*.al\n'
  printf 'scope=%s\n' "$1"
  printf 'source_count=%s\n' "$2"
  printf 'backend_order=x86_64,aarch64,riscv64,wasm\n'
  printf 'excluded_pairs=%s\n' "$EXCLUDED_PAIRS"
  printf 'row_count=%s\n' "$3"
  printf 'columns=backend<TAB>path<TAB>phase<TAB>exit<TAB>stdout_sha256<TAB>stderr_sha256\n'
  cat "$4"
}
write_manifest "every source (the observation of this walk; never committed)" "$SRC_COUNT" "$ROWS" "$BODY" > "$OBSERVED"
write_manifest "sources with no ## expect: directive, and directive sources that print (#1126 S3)" \
  "$SCOPED_SRC" "$SCOPED_ROWS" "$WORK/scoped" > "$GENERATED"

if [ "$MODE" = write ]; then
  [ -f "$MANIFEST" ] || selftest "$GENERATED" || exit 2
  cp "$GENERATED" "$MANIFEST"
  echo "corpus manifest: WROTE $MANIFEST ($SCOPED_ROWS rows of $SCOPED_SRC sources in scope; $ROWS rows, $SRC_COUNT sources observed, all four backends ran)"
  exit 0
fi

## The predicted delta, when the feature declares one. LIVE means the committed manifest is exactly
## the one the prediction was made against, and then the delta — not a byte-for-byte match — is the
## verdict: a fresh run that equals the committed manifest is RED here (every declared pair went
## unrealised), and one that differs by anything but the declared rows is RED too. Spent or stale, the
## delta says nothing about this tree and the ordinary match below decides, so a delta file left on
## `main` after its oracle commit can never turn a later mismatch green.
DELTA_FILE="$ROOT/$DELTA_FILE_REL"
if [ -f "$DELTA_FILE" ]; then
  delta_check "$MANIFEST" "$GENERATED" "$DELTA_FILE"; drc=$?
  case "$drc" in
    0)
      echo "corpus manifest: match by the declared delta — the fresh walk differs from the committed manifest"
      echo "corpus manifest:   by exactly the $DELTA_PAIRS pair(s) of $DELTA_FILE_REL ($ROWS rows, $SRC_COUNT sources, all four backends ran)"
      echo "corpus manifest:   ORACLE COMMIT OWED — $GENERATED (sha256 $(sha_file "$GENERATED"))"
      echo "corpus manifest:   is the oracle, byte for byte; scripts/land.sh commits it and checks it with cmp."
      explain_manifest "$MANIFEST" "$GENERATED"
      exit 0 ;;
    1)
      echo "corpus manifest: MISMATCH against the declared delta in $DELTA_FILE_REL (report above)" >&2
      explain_manifest "$MANIFEST" "$GENERATED" >&2
      exit 1 ;;
    3)
      echo "corpus manifest: note — $DELTA_FILE_REL is INERT ($DELTA_STATE): it was predicted against another"
      echo "corpus manifest:   committed manifest, so the fresh walk must match byte for byte." ;;
    *)
      echo "corpus manifest: $DELTA_FILE_REL is malformed (see above); refusing to read it as a prediction" >&2
      exit 2 ;;
  esac
fi

if compare_manifest "$MANIFEST" "$GENERATED" "corpus manifest: MISMATCH"; then
  echo "corpus manifest: match ($SCOPED_ROWS rows of $SCOPED_SRC sources in scope; $ROWS rows, $SRC_COUNT sources observed, all four backends ran)"
  exit 0
fi
echo "  Re-run with ALATYR_CORPUS_KEEP=1 to retain each pair's artifacts under $WORK." >&2
echo "  An INTENTIONAL behaviour change declares it: from a native x86_64 walk of the PR," >&2
echo "    scripts/corpus_manifest.sh --emit-expected scripts/corpus.manifest $GENERATED > $DELTA_FILE_REL" >&2
echo "  and commits that file in the PR (CONTRIBUTING.md, \"An intentional behaviour change\")." >&2
exit 1
