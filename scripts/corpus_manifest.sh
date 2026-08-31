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
#   • provenance — the compiler under test is named with its sha256, a `target/debug/alatyr` older than the
#     newest `src/`/`lib/` file is refused, and a compiler supplied via `ALATYR_CORPUS_CC` that differs
#     from this checkout's own is refused unless the caller says so out loud;
#   • a missing cross tool is exit 2, never a partial green.
#
# ## Usage
#
#   scripts/corpus_manifest.sh [--check|--write|--self-test]
#     --check (default)  regenerate and compare byte-for-byte with scripts/corpus.manifest
#     --write            overwrite scripts/corpus.manifest (an intentional behaviour change owns this)
#     --explain A B      read two manifests JOINED on (backend, path), grouped by severity class.
#                        A regeneration's commit message carries this output verbatim.
#     --self-test        run the detector, normalization and frame-layout self-tests only; never walk
#                        the corpus or write scripts/corpus.manifest
#
#   ALATYR_CORPUS_CC        absolute compiler to exercise (default: this checkout's target/debug/alatyr)
#   ALATYR_CORPUS_TIMEOUT   seconds per child process, build phases included (default: 30)
#   ALATYR_CORPUS_JOBS      sources in flight (default: min(nproc, 8); 1 = serial)
#   ALATYR_CORPUS_KEEP=1    keep every artifact for inspection instead of freeing it per source
#   ALATYR_CORPUS_ALLOW_FOREIGN_CC=1   permit an ALATYR_CORPUS_CC that is not this checkout's compiler
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
  record wasm "$rel" run "$?" "$d/r.out" "$d/r.err"
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
## 30 s, not 10: the slowest single child in the corpus is `alatyr -o … test/uint256.al` at 2.2 s
## unloaded (it assembles and links; the other three backends only emit GAS, ≤0.03 s each), and with
## eight sources in flight a 10 s ceiling left a margin small enough that a busy machine could turn a
## spurious `compile_timeout` into a RED gate — the worst failure mode for a committed baseline. The
## ceiling exists to stop a LOOPING compiler, not to police compile time.
TIMEOUT_SECS="${ALATYR_CORPUS_TIMEOUT:-30}"
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
    --help|-h) usage; exit 0 ;;
    *) echo "corpus manifest: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

die() { echo "corpus manifest: $*" >&2; exit 2; }

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

## Compare two manifests. Returns 0 when identical. On a mismatch it says FIRST how many rows differ,
## then shows a bounded sample and states how many rows it withheld — the first cut printed
## `diff -u | head -80` with no count, so a 24-row change was reported as 15 rows with nothing saying
## that 9 were hidden. Sets DIFF_LINES.
DIFF_SHOW="${ALATYR_CORPUS_DIFF_SHOW:-60}"
## Join two manifests on (backend, path) and print each difference under its severity class.
## `--explain <old> <new>` exposes it directly; `--check` calls it on a mismatch. EXPLAIN_CAP
## bounds the sample PER CLASS, never globally: a global bound can hide a whole class.
EXPLAIN_CAP="${ALATYR_CORPUS_EXPLAIN_CAP:-12}"
explain_manifest() { # baseline candidate
  awk -v CAP="$EXPLAIN_CAP" '## Join two manifests on (backend, path) and classify each difference. Reading the raw `diff -u`
## positionally is WRONG and has nearly cost a landing: added and removed rows do not pair up, so a
## shifted row invents transitions that are not there, and a global `head` can truncate away an entire
## severity class. Eight `run -> assemble/1` regressions once sat inside 23 genuine wins.
BEGIN { FS = "\t"; OFS = "\t" }
FNR == NR {
  if (NF == 6 && $1 ~ /^(x86_64|aarch64|riscv64|wasm)$/) { k = $1 SUBSEP $2; o[k] = $3 "/" $4 "/" $5 "/" $6 }
  next
}
NF == 6 && $1 ~ /^(x86_64|aarch64|riscv64|wasm)$/ {
  k = $1 SUBSEP $2; n[k] = $3 "/" $4 "/" $5 "/" $6
}
END {
  for (k in o) if (!(k in n)) cls[k] = "REMOVED"
  for (k in n) {
    if (!(k in o)) { cls[k] = "ADDED"; continue }
    if (o[k] == n[k]) continue
    split(o[k], a, "/"); split(n[k], b, "/")
    orun = (a[1] == "run"); nrun = (b[1] == "run")
    if (orun && !nrun)            cls[k] = "NO-LONGER-RUNS"
    else if (!orun && nrun)       cls[k] = "NOW-RUNS"
    else if (orun && a[2] != b[2]) cls[k] = "EXIT-CHANGED"
    else if (orun)                cls[k] = "OUTPUT-CHANGED"
    else if (a[1] != b[1])        cls[k] = "PHASE-CHANGED"
    else                          cls[k] = "DETAIL-CHANGED"
  }
  nc = split("NO-LONGER-RUNS EXIT-CHANGED REMOVED PHASE-CHANGED DETAIL-CHANGED OUTPUT-CHANGED NOW-RUNS ADDED", ord, " ")
  desc["NO-LONGER-RUNS"] = "was running, now refused by an earlier phase — a REGRESSION"
  desc["EXIT-CHANGED"]   = "ran before and after, different exit — a VALUE change"
  desc["REMOVED"]        = "the pair is gone from the fresh run — coverage lost"
  desc["PHASE-CHANGED"]  = "refused before and after, at a different phase"
  desc["DETAIL-CHANGED"] = "same phase, different exit or captured streams"
  desc["OUTPUT-CHANGED"] = "ran with the same exit, different stdout/stderr"
  desc["NOW-RUNS"]       = "was refused, now runs — a WIN"
  desc["ADDED"]          = "new pair in the fresh run — new coverage"
  total = 0
  for (k in cls) { total++; cnt[cls[k]]++; split(k, kk, SUBSEP); per[cls[k]] SUBSEP kk[1]; bk[cls[k] SUBSEP kk[1]]++ }
  if (total == 0) { print "corpus manifest: no (backend,path) pair differs"; exit 0 }
  printf "corpus manifest: %d differing pairs, joined on (backend, path)\n", total
  for (i = 1; i <= nc; i++) {
    c = ord[i]; if (!(c in cnt)) continue
    line = ""
    nb = split("x86_64 aarch64 riscv64 wasm", bo, " ")
    for (j = 1; j <= nb; j++) if ((c SUBSEP bo[j]) in bk) line = line sprintf(" %s %d", bo[j], bk[c SUBSEP bo[j]])
    printf "\n  %-15s %4d pair(s)  [%s ]\n      %s\n", c, cnt[c], line, desc[c]
    shown = 0
    for (k in cls) {
      if (cls[k] != c) continue
      if (shown >= CAP) continue
      split(k, kk, SUBSEP)
      ov = (k in o) ? o[k] : "-"; nv = (k in n) ? n[k] : "-"
      split(ov, a, "/"); split(nv, b, "/")
      printf "      %-8s %-52s %s -> %s\n", kk[1], kk[2], \
        (ov == "-" ? "-" : a[1] "/" a[2]), (nv == "-" ? "-" : b[1] "/" b[2])
      shown++
    }
    if (cnt[c] > shown) printf "      … %d more in this class (the count above is complete)\n", cnt[c] - shown
  }
  exit 0
}
' "$1" "$2"
}

if [ "$MODE" = explain ]; then
  for f in "$EXPLAIN_A" "$EXPLAIN_B"; do
    [ -f "$f" ] || die "no such manifest: $f"
  done
  explain_manifest "$EXPLAIN_A" "$EXPLAIN_B"
  exit 0
fi

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
  awk -F'\t' 'NF==6 && $3=="run"{print; n++} n>=4{exit}' "$src" > "$a"
  if [ "$(grep -c '' "$a")" -lt 4 ]; then
    echo "corpus manifest: classifier self-test FAILED — fewer than 4 running rows to plant into" >&2
    return 1
  fi
  awk -F'\t' 'BEGIN{OFS="\t"}
    NR==1 { $3="assemble"; $4=1; print; next }              # -> NO-LONGER-RUNS
    NR==2 { $4=$4+1;       print; next }                    # -> EXIT-CHANGED
    NR==3 { $5="fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"; print; next }  # -> OUTPUT-CHANGED
    NR==4 { next }                                          # -> REMOVED
    {print}
    END { print "wasm\ttest/_classifier_selftest.al\trun\t42\t" \
                "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\t" \
                "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee" }  # -> ADDED
  ' "$a" > "$b"
  explain_manifest "$a" "$b" > "$out" 2>&1 || true
  for c in NO-LONGER-RUNS:1 EXIT-CHANGED:1 OUTPUT-CHANGED:1 REMOVED:1 ADDED:1; do
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
ROWS="$(body_rows "$BODY")"
if [ "$ROWS" != "$EXPECT_ROWS" ]; then
  die "the body holds $ROWS rows, want $EXPECT_ROWS ($SRC_COUNT × 4 − $EXCLUDED_PAIRS)"
fi
## Two counts per backend, and both must be non-vacuous.
##   RUN_<b>  — sources that reached phase `run`. Zero means the backend never executed a program:
##              measured with a shimmed always-failing `aarch64-as`, `--write` blessed a baseline
##              holding ZERO aarch64 `run` rows and exited 0.
##   EXIT_<b> — DISTINCT exit codes among those rows. One means the runner answered the same thing for
##              every program, which is what a broken runner looks like from here: measured, running
##              wasmtime with an unwritable cache directory made all 1 235 wasm `run` rows `exit 1`,
##              a whole column that passed the RUN_ check while recording nothing.
eval "$(awk -F'\t' '$3=="run" {c[$1]++; k[$1 FS $4]=1}
                     END{for (b in c) printf "RUN_%s=%d\n", b, c[b];
                         for (x in k) {split(x, a, FS); d[a[1]]++}
                         for (b in d) printf "EXIT_%s=%d\n", b, d[b]}' "$BODY")"
vac=0
for b in x86_64 aarch64 riscv64 wasm; do
  eval "n=\${RUN_$b:-0}; d=\${EXIT_$b:-0}"
  if [ "$n" -lt 1 ]; then
    echo "corpus manifest: backend $b reached phase 'run' for ZERO sources — it never executed a" >&2
    echo "  single program, so its rows record nothing about behaviour. Refusing to report a result." >&2
    vac=1
  elif [ "$d" -lt 2 ]; then
    echo "corpus manifest: backend $b ran $n programs and every one exited the SAME way — its runner" >&2
    echo "  is answering independently of the program, so the column is vacuous. Refusing to report." >&2
    vac=1
  fi
done
[ "$vac" = 0 ] || exit 2
## A `*_timeout` row is the one observation that can move because the MACHINE was busy rather than
## because the compiler changed, so it is never silent.
TIMEOUTS="$(awk -F'\t' '$3 ~ /_timeout$/ {n++} END{print n+0}' "$BODY")"
if [ "$TIMEOUTS" != 0 ]; then
  echo "corpus manifest: WARNING — $TIMEOUTS row(s) hit the ${TIMEOUT_SECS}s ceiling and are recorded as" >&2
  echo "  a '*_timeout' phase. That is either a hang or a machine too busy to finish in time; a timeout" >&2
  echo "  row is the one kind this oracle cannot call reproducible." >&2
fi
echo "corpus manifest: rows=$ROWS  phase run / distinct exits:" \
     "x86_64=${RUN_x86_64:-0}/${EXIT_x86_64:-0}" "aarch64=${RUN_aarch64:-0}/${EXIT_aarch64:-0}" \
     "riscv64=${RUN_riscv64:-0}/${EXIT_riscv64:-0}" "wasm=${RUN_wasm:-0}/${EXIT_wasm:-0}" "(${elapsed}s)"

{
  printf '# Alatyr per-file corpus manifest; generated by scripts/corpus_manifest.sh\n'
  printf '# Paths in a row are relative to this checkout; captured streams are normalized before\n'
  printf '# hashing, so the file is reproducible in a checkout at a DIFFERENT path.\n'
  printf 'format=alatyr-corpus-manifest-v2\n'
  ## Read this as the GIT PATHSPEC it is, not as a shell glob: git's `*` matches `/`, so the one
  ## pattern also selects the multi-file package fixtures under test/package/**. That is why
  ## source_count is ~1663 and not the ~1352 files a shell `ls test/*.al` would show. The literal is
  ## part of the compared file, so changing its wording costs a full oracle regeneration.
  printf 'source_glob=test/*.al\n'
  printf 'source_count=%s\n' "$SRC_COUNT"
  printf 'backend_order=x86_64,aarch64,riscv64,wasm\n'
  printf 'excluded_pairs=%s\n' "$EXCLUDED_PAIRS"
  printf 'row_count=%s\n' "$ROWS"
  printf 'columns=backend<TAB>path<TAB>phase<TAB>exit<TAB>stdout_sha256<TAB>stderr_sha256\n'
  cat "$BODY"
} > "$GENERATED"

if [ "$MODE" = write ]; then
  [ -f "$MANIFEST" ] || selftest "$GENERATED" || exit 2
  cp "$GENERATED" "$MANIFEST"
  echo "corpus manifest: WROTE $MANIFEST ($ROWS rows, $SRC_COUNT sources, all four backends ran)"
  exit 0
fi

if compare_manifest "$MANIFEST" "$GENERATED" "corpus manifest: MISMATCH"; then
  echo "corpus manifest: match ($ROWS rows, $SRC_COUNT sources, all four backends ran)"
  exit 0
fi
echo "  Re-run with ALATYR_CORPUS_KEEP=1 to retain each pair's artifacts under $WORK." >&2
echo "  An INTENTIONAL behaviour change owns a reviewed 'scripts/corpus_manifest.sh --write'." >&2
exit 1
