#!/usr/bin/env bash
# scripts/e2e.sh — the AUTHORITATIVE end-to-end gate for the self-hosted compiler.
#
# Each `test/<name>.al` is a single-file program with a `main -> u64`; the self-built compiler
# builds+links it to a static binary, runs it, and the exit code is checked against the FIXTURE
# TABLE below. Run inside the dev shell (`nix develop`) so `as`/`ld` are on PATH. Builds Stage1 from
# the committed seed. Exit 0 = all green.
#
# ## How this file is organised (read this before editing it)
#
#   1. this prologue                — Stage1, the compiler snapshot, the driver's configuration
#   2. the HELPERS                  — one function per assertion KIND (`run`, `check_accept`, …)
#   3. `_e2e_arm`                   — the driver arms every helper (see below)
#   4. the FIXTURE TABLE            — ~1500 one-line rows, each a call to a helper
#   5. the DRIVER                   — schedules the rows, runs them, prints them, reports
#
# **Adding a fixture** is unchanged: append a `run …` / `check_accept …` / `build_reject_has …` line
# to the table wherever it belongs. **Adding a new KIND** means adding a helper function, and the
# helper must be defined in region 2 — *above* `_e2e_arm` — or the gate fails loudly and says so
# (`_e2e_check_armed`). Its call sites can be anywhere in the table.
#
# ## The rows run in PARALLEL
#
# Every row is independent — it compiles one program and inspects the result — so the suite is
# embarrassingly parallel, and it used to run entirely serially: 4 m 40 s measured on 12 cores, of
# which one row (`ext_test env_size_test`) is 83 s by itself. `$(nproc)` workers now execute the
# rows; `ALATYR_JOBS=1` puts it back in strict table order, which is what to use when a failure is
# confusing and you want it reproduced in sequence.
#
# The mechanism is deliberately indirect, because the fixture table must NOT have to change:
#
#   * `_e2e_arm` CLONES every helper `f` to `t_f` (via `declare -f`, so the clone is bash's own
#     serialisation of the original — byte-identical, verified by `_e2e_selftest`) and replaces `f`
#     with a one-line stub that calls `_dispatch f "$@"`.
#   * The table then executes with `E2E_PHASE=record`: every row RECORDS its own command line
#     (`printf %q`, so quoting survives) instead of running. Recording cannot skip a row — a row IS
#     a function call, and every helper is armed — which is the property the old fast runner did not
#     have: it re-derived the table with a `grep` for 7 of the 30+ kinds and silently covered ~92%.
#   * The driver then runs the recorded rows on `$JOBS` workers, each in its own subshell with its
#     own scratch directory `$T`, and prints the collected output in TABLE ORDER — never completion
#     order — so two runs of the same tree produce byte-identical logs.
#   * A helper called at row time reaches `t_f` through the same stub (`E2E_PHASE=run`), so helpers
#     that call other helpers (`fmt_test_has` -> `fmt_test`) keep working.
#
# ## Per-row isolation (the two hazards this cost us)
#
#   * Artifacts are keyed by the ROW, not by the fixture name: `$T` is `target/e2e/s/<row>/`. Two
#     rows naming the same fixture are common (`run named_args 42` is registered twice, and dozens
#     of names appear under several kinds), and with name-keyed artifacts they would overwrite each
#     other's binaries mid-run. Nothing in the helpers writes to a fixed path outside `$T` any more
#     — in particular `fmt_test` used to copy through `/tmp/fmtrun.al`, a path SHARED by every
#     worktree on the machine (AGENTS.md: fixed paths in /tmp are shared).
#   * The compiler under test is an immutable SNAPSHOT of Stage1, not `target/debug/alatyr` itself:
#     `ext_test env_size_test` rebuilds its package fixture artifacts in place 8 times (that is what it tests),
#     and rewriting the binary that 12 workers are executing is a race — `ld` gets ETXTBSY, or a
#     worker execs a half-written file. The snapshot keeps the required layout, because the compiler
#     resolves its stdlib as `dirname(/proc/self/exe)/../lib` (AGENTS.md: never move a built
#     compiler out of a directory that has `../lib`).
#
# ## Proof of work
#
# A green run prints its counts (`rows=`, `executed=`, `assertions=`, `missing=`, `failed=`) and
# fails if any row produced no result, so a runner that quietly dropped rows cannot report green.
# `_e2e_selftest` runs first and proves, every time, that the machinery still FAILS when it should.
#
# ## Environment
#
#   ALATYR_JOBS=<n>            workers (default `nproc`); 1 = strict serial, in table order
#   ALATYR_E2E_FILTER=<sub>    run only rows whose command contains <sub> (iteration; NOT the gate)
#   ALATYR_E2E_REBUILD=stale   rebuild Stage1 only when older than src//lib/ (iteration)
#   ALATYR_E2E_TEST_DIR=<dir>  fixture root (default `test/`; used by the self-test)
set -u
# AGENTS.md: "Run everything with `ulimit -c 0` — fail-loud traps drop 8 MB core dumps." Several
# fixtures trap ON PURPOSE (that IS the assertion), so the suite must set this itself rather than
# trust whoever invoked it; the sweeps already do.
ulimit -c 0 2>/dev/null || true
# C locale: `sort` order and numeric formatting must not depend on the invoking shell, or the log is
# not comparable between runs. (`EPOCHREALTIME`'s separator is locale-dependent — see `_row_exec`.)
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

JOBS="${ALATYR_JOBS:-$(nproc 2>/dev/null || echo 4)}"
case "$JOBS" in ''|*[!0-9]*) echo "FAIL: ALATYR_JOBS must be a positive integer, got '$JOBS'"; exit 1 ;; esac
[ "$JOBS" -ge 1 ] || { echo "FAIL: ALATYR_JOBS must be >= 1, got '$JOBS'"; exit 1; }
FILTER="${ALATYR_E2E_FILTER:-}"
E2E_TEST="${ALATYR_E2E_TEST_DIR:-$ROOT/test}"
WORK="$ROOT/target/e2e"

STAGE1="$ROOT/target/debug/alatyr"
if [ ! -x "$STAGE1" ] && [ -x "$ROOT/target/alatyr" ]; then STAGE1="$ROOT/target/alatyr"; fi
rebuild=1
if [ "${ALATYR_E2E_REBUILD:-always}" = stale ]; then
  rebuild=0
  [ -x "$STAGE1" ] || rebuild=1
  if [ "$rebuild" = 0 ] && [ -n "$(find src lib -newer "$STAGE1" -print -quit 2>/dev/null)" ]; then rebuild=1; fi
fi
if [ "$rebuild" = 1 ]; then
  echo "=== building Stage1 (seed builds the current tree) ==="
  rm -f "$ROOT/target/alatyr" "$ROOT/target/alatyr.s" "$ROOT/target/alatyr.o"
  rm -f "$ROOT/target/debug/alatyr" "$ROOT/target/debug/alatyr.s" "$ROOT/target/debug/alatyr.o"
  "$ROOT/seed/alatyr" build "$ROOT/package.al" >/dev/null 2>&1
  seed_rc=$?
  [ "$seed_rc" = 0 ] || { echo "FAIL: seed build (rc=$seed_rc)"; exit 1; }
  if [ -x "$ROOT/target/debug/alatyr" ]; then
    STAGE1="$ROOT/target/debug/alatyr"
  elif [ -x "$ROOT/target/alatyr" ]; then
    STAGE1="$ROOT/target/alatyr"
    echo "bootstrap transition: e2e used legacy target/alatyr; fixpoint remains the reseed decision"
  else
    echo "FAIL: seed created neither target/debug/alatyr nor legacy target/alatyr"; exit 1
  fi
fi
[ -x "$STAGE1" ] || { echo "FAIL: no self-host compiler at $STAGE1"; exit 1; }
mkdir -p target

# The immutable compiler snapshot (see "Per-row isolation" above). `$ROOT/lib` is symlinked, not
# copied, so the stdlib under test is the tree's own.
rm -rf "$WORK"
mkdir -p "$WORK/cc/bin" "$WORK/out" "$WORK/rc" "$WORK/s"
cp "$STAGE1" "$WORK/cc/bin/alatyr" || { echo "FAIL: could not snapshot $STAGE1"; exit 1; }
ln -sfn "$ROOT/lib" "$WORK/cc/lib" || { echo "FAIL: could not link the stdlib next to the snapshot"; exit 1; }
CC="$WORK/cc/bin/alatyr"
cmp -s "$STAGE1" "$CC" || { echo "FAIL: the compiler snapshot is not byte-identical to $STAGE1"; exit 1; }

# PRISTINE copies of the two fixture subtrees that rows BUILD IN. `test/package/<d>` and
# `test/link/<d>` are not read-only fixtures: ~20 rows (plus scripts/package_cli_test.sh, which this
# suite runs as a row) build inside them and `rm -rf` their `target/` afterwards. Concurrently that
# is a race, and it was measured as `root_package(dep_declared/package.al): run got 19` — a spawn
# failure, because another row had just deleted the directory under it. Each row copies what it needs
# out of these snapshots (`_fixture_tree`), so no row writes into the repository's own `test/` and
# the gate no longer leaves `test/package/*/target/` behind. The whole SUBTREE is copied, not the one
# package, because path dependencies are relative (`DepSource.Path("../dep_lib")`).
mkdir -p "$WORK/tree"
for _sub in package link; do
  if [ -d "$E2E_TEST/$_sub" ]; then
    cp -r "$E2E_TEST/$_sub" "$WORK/tree/$_sub" || { echo "FAIL: could not snapshot $E2E_TEST/$_sub"; exit 1; }
    find "$WORK/tree/$_sub" -type d -name target -prune -exec rm -rf {} + 2>/dev/null
  fi
done
unset _sub

# `$T` is the CURRENT ROW's private scratch directory; the driver sets it per row. Assigning it here
# (rather than leaving it unset) keeps `set -u` from turning a stray direct helper call into an
# obscure unbound-variable abort instead of a legible path.
T="$WORK/s/unassigned"
mkdir -p "$T"
fail=0

# Every produced target that this runner executes goes through one finite deadline.  The wrapper
# shell writes the child's status only after the child has returned; when the marker is absent, the
# timeout killed the wrapper before it could report completion.  This deliberately does not use
# timeout's status alone: a legal target exit of 124 (or 137) must remain a target result, not become
# a false timeout.  The one-second kill grace bounds a child that ignores TERM without touching the
# longer-running external scripts below.
E2E_RUNTIME_TIMEOUT=10s
E2E_RUNTIME_KILL_AFTER=1s
E2E_RUNTIME_STATE=not-run

_e2e_exec_timed() { # duration, command ...
  local _e2e_duration="$1" _e2e_marker _e2e_timeout_rc _e2e_child_rc
  shift
  _e2e_marker="$T/.runtime-${BASHPID}-${RANDOM}"
  rm -f "$_e2e_marker"
  timeout --kill-after="$E2E_RUNTIME_KILL_AFTER" "$_e2e_duration" \
    bash -c '
      _e2e_status_file=$1
      shift
      "$@"
      _e2e_child_rc=$?
      printf "%s\n" "$_e2e_child_rc" > "$_e2e_status_file"
      exit "$_e2e_child_rc"
    ' _ "$_e2e_marker" "$@"
  _e2e_timeout_rc=$?
  if [ -s "$_e2e_marker" ]; then
    IFS= read -r _e2e_child_rc < "$_e2e_marker"
    rm -f "$_e2e_marker"
    case "$_e2e_child_rc" in
      ''|*[!0-9]*)
        E2E_RUNTIME_STATE=runner-error
        return 125
        ;;
    esac
    E2E_RUNTIME_STATE=exited
    return "$_e2e_child_rc"
  fi
  rm -f "$_e2e_marker"
  if [ "$_e2e_timeout_rc" = 124 ] || [ "$_e2e_timeout_rc" = 137 ]; then
    E2E_RUNTIME_STATE=timeout
    return 124
  fi
  E2E_RUNTIME_STATE=runner-error
  return "$_e2e_timeout_rc"
}

_e2e_exec() {
  _e2e_exec_timed "$E2E_RUNTIME_TIMEOUT" "$@"
}

_e2e_exec_capture() { # stdout-file, command ...
  local _e2e_stdout="$1"
  shift
  _e2e_exec "$@" >"$_e2e_stdout"
}

_e2e_exec_capture_combined() { # stdout+stderr-file, command ...
  local _e2e_output="$1"
  shift
  _e2e_exec "$@" >"$_e2e_output" 2>&1
}

_e2e_exec_in() { # directory, command ...
  local _e2e_dir="$1" _e2e_saved_pwd="$PWD" _e2e_rc
  shift
  cd "$_e2e_dir" || { E2E_RUNTIME_STATE=runner-error; return 125; }
  _e2e_exec "$@"
  _e2e_rc=$?
  cd "$_e2e_saved_pwd" || { E2E_RUNTIME_STATE=runner-error; return 125; }
  return "$_e2e_rc"
}

_e2e_exec_capture_in() { # stdout-file, directory, command ...
  local _e2e_stdout="$1" _e2e_dir="$2" _e2e_saved_pwd="$PWD" _e2e_rc
  shift 2
  cd "$_e2e_dir" || { E2E_RUNTIME_STATE=runner-error; return 125; }
  _e2e_exec_capture "$_e2e_stdout" "$@"
  _e2e_rc=$?
  cd "$_e2e_saved_pwd" || { E2E_RUNTIME_STATE=runner-error; return 125; }
  return "$_e2e_rc"
}

_e2e_runtime_failure() { # label, observed-status
  local _e2e_label="$1" _e2e_rc="$2" _e2e_state="${3:-$E2E_RUNTIME_STATE}"
  case "$_e2e_state" in
    timeout)
      echo "FAIL $_e2e_label: runtime timeout after $E2E_RUNTIME_TIMEOUT"
      fail=1
      return 0
      ;;
    runner-error)
      echo "FAIL $_e2e_label: runtime wrapper failed (rc=$_e2e_rc)"
      fail=1
      return 0
      ;;
  esac
  return 1
}

## A row-private copy of a fixture subtree that this row is going to BUILD in (see the snapshot note
## in the prologue). Echoes the row-private root; the copy is made once per row, on first use.
_fixture_tree() { # subtree: package | link
  if [ ! -d "$T/tree/$1" ]; then
    mkdir -p "$T/tree"
    cp -r "$WORK/tree/$1" "$T/tree/$1" || { echo "FAIL: could not copy the $1 fixture subtree into $T"; return 1; }
  fi
  printf '%s' "$T/tree/$1"
}

# name -> expected exit code
run() { # name, want
  src="$E2E_TEST/$1.al"
  [ -f "$src" ] || { echo "MISS $1: no $src"; fail=1; return; }
  out="$T/e2e_$1.out"
  "$CC" -o "$out" "$src" >/dev/null 2>&1 || { echo "FAIL $1: compile/link"; fail=1; return; }
  _e2e_exec "$out" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "$1" "$got"; then return; fi
  if [ "$got" = "$2" ]; then echo "ok   $1: $got"; else echo "FAIL $1: got $got want $2"; fail=1; fi
}

# MOD §6.3 (@export): build+run (exit-code check) AND assert the EXACT linker symbol is present as a
# global in the binary (nm). x86_64-only (not matched by the sweeps' `^run [a-z]` grep).
check_export() { # name, want-exit, symbol
  src="$E2E_TEST/$1.al"
  [ -f "$src" ] || { echo "MISS $1: no $src"; fail=1; return; }
  out="$T/e2e_$1.out"
  "$CC" -o "$out" "$src" >/dev/null 2>&1 || { echo "FAIL $1: compile/link"; fail=1; return; }
  _e2e_exec "$out" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "$1" "$got"; then return; fi
  if [ "$got" != "$2" ]; then echo "FAIL $1: got $got want $2"; fail=1; return; fi
  if nm "$out" 2>/dev/null | grep -qE " T $3\$"; then echo "ok   $1: $got + exported $3"; else echo "FAIL $1: symbol $3 not a global"; fail=1; fi
}

# Declarations §2.3 / Codegen §3.5 — a value-position @inline must be substituted at its direct call
# site rather than silently falling back to an ordinary call.
check_inline_value() { # name, callee-symbol
  src="$E2E_TEST/$1.al"
  gas="$T/e2e_$1_inline.s"
  [ -f "$src" ] || { echo "MISS $1: no $src"; fail=1; return; }
  "$CC" "$src" > "$gas" 2>/dev/null || { echo "FAIL $1(inline): emit"; fail=1; return; }
  if grep -qE "call[[:space:]]+$2$" "$gas"; then
    echo "FAIL $1(inline): emitted call to $2"; fail=1; return
  fi
  echo "ok   $1(inline): substituted call"
}

# x86_64-ONLY build+run (same as run, but NOT matched by the sweeps' `^run [a-z]` grep — for raw-asm
# fixtures whose register/syscall surface is x86_64-specific; other-arch register surfaces are follow-ups).
run_x86() { # name, want
  src="$E2E_TEST/$1.al"
  [ -f "$src" ] || { echo "MISS $1: no $src"; fail=1; return; }
  out="$T/e2e_$1.out"
  "$CC" -o "$out" "$src" >/dev/null 2>&1 || { echo "FAIL $1: compile/link"; fail=1; return; }
  _e2e_exec "$out" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "$1" "$got"; then return; fi
  if [ "$got" = "$2" ]; then echo "ok   $1: $got"; else echo "FAIL $1: got $got want $2"; fail=1; fi
}

# Control Flow §2.1–§2.3 / x86_64 appendix §3 — a direct code-point transfer must be a GAS jump to
# the named local target, not an ordinary call or an unresolved symbol. The target prefix is compiler
# generated, so pair the one emitted `done` label with its transfer rather than asserting a pointer-derived
# spelling. This row is x86-only: the non-x86/WAT follow-ups are deliberately outside issue #207.
check_x86_gas() { # name
  src="$E2E_TEST/$1.al"
  gas="$T/e2e_$1.gas"
  [ -f "$src" ] || { echo "MISS $1: no $src"; fail=1; return; }
  "$CC" "$src" > "$gas" 2>/dev/null || { echo "FAIL $1(gas): emit"; fail=1; return; }
  label="$(grep -E '^\.Lcp_[^:]*_done:$' "$gas" | sed 's/:$//' | sed -n '1p')"
  [ -n "$label" ] || { echo "FAIL $1(gas): named local target missing"; fail=1; return; }
  if grep -qE "^[[:space:]]+jmp[[:space:]]+$label$" "$gas"; then
    echo "ok   $1(gas): direct jmp to $label"
  else
    echo "FAIL $1(gas): direct jmp to $label missing"; fail=1
  fi
}

# x86_64-only build+run with a checked-in exact stdout golden and exit code.
run_x86_out() { # name, want-exit; expected output is test/<name>.out
  src="$E2E_TEST/$1.al"
  want="$E2E_TEST/$1.out"
  [ -f "$src" ] || { echo "MISS $1: no $src"; fail=1; return; }
  [ -f "$want" ] || { echo "MISS $1: no $want"; fail=1; return; }
  out="$T/e2e_$1.out"
  gotout="$T/e2e_$1.stdout"
  "$CC" -o "$out" "$src" >/dev/null 2>&1 || { echo "FAIL $1: compile/link"; fail=1; return; }
  _e2e_exec_capture "$gotout" "$out" 2>/dev/null; got=$?
  if _e2e_runtime_failure "$1" "$got"; then return; fi
  if [ "$got" = "$2" ] && cmp -s "$gotout" "$want"; then
    echo "ok   $1: exact stdout + $got"
  else
    echo "FAIL $1: exit=$got want=$2 or stdout mismatch"
    fail=1
  fi
}

# x86_64-only expected runtime trap. Disable core dumps so the acceptance path never litters the
# checkout; 128+signal is the shell-visible status (SIGILL = 132 for the compiler's checked trap).
run_x86_trap() { # name, want-status
  src="$E2E_TEST/$1.al"
  [ -f "$src" ] || { echo "MISS $1: no $src"; fail=1; return; }
  out="$T/e2e_$1.out"
  "$CC" -o "$out" "$src" >/dev/null 2>&1 || { echo "FAIL $1: compile/link"; fail=1; return; }
  _e2e_exec "$out" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "$1" "$got"; then return; fi
  if [ "$got" = "$2" ]; then echo "ok   $1: trapped $got"; else echo "FAIL $1: got $got want trap $2"; fail=1; fi
}

# `alatyr run` must report the SAME status as build+execute for a TRAPPING program (128 + signal).
# Guards cli::wexit's wait4-status decode: an unconditional WEXITSTATUS reported a SIGNAL-terminated child
# as exit 0, so `alatyr run` called a trapping program a clean success — a trap-detection hole in the
# user-facing command, and a trap for any verification loop built on it. (The rest of this harness builds
# and executes, which is why it never noticed.)
run_cli_trap() { # name, want-status
  src="$E2E_TEST/$1.al"
  [ -f "$src" ] || { echo "MISS cli_run_$1: no $src"; fail=1; return; }
  _e2e_exec "$CC" run "$src" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "cli_run_$1" "$got"; then return; fi
  if [ "$got" = "$2" ]; then echo "ok   cli_run_$1: run reported trap $got"; else echo "FAIL cli_run_$1: got $got want $2"; fail=1; fi
}

# `run <source> -- <args…>` separates the compiler's source-path list from the program's argv. The
# target reads argv through the spec-defined std::os::args surface; a source-path leak would try to
# compile `--`/the value and fail before the target starts.
run_cli_args() { # name, want-status
  src="$E2E_TEST/$1.al"
  [ -f "$src" ] || { echo "MISS cli_run_$1: no $src"; fail=1; return; }
  _e2e_exec "$CC" run "$src" -- "cli-arg-0" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "cli_run_$1" "$got"; then return; fi
  if [ "$got" = "$2" ]; then echo "ok   cli_run_$1: forwarded program argv"; else echo "FAIL cli_run_$1: got $got want $2"; fail=1; fi
}

# `std::os::args` must keep reading when one argument crosses its initial staging chunk. Generate the
# payload here so the fixture can assert exact length and bytes without storing a giant source literal.
run_cli_args_sized() { # name, argument-length, fill-byte, want-status, optional trailing argument
  src="$E2E_TEST/$1.al"
  [ -f "$src" ] || { echo "MISS cli_run_$1: no $src"; fail=1; return; }
  long_arg="$(awk -v n="$2" -v c="$3" 'BEGIN { for (i = 0; i < n; i++) printf "%s", c }')"
  if [ "$#" -ge 5 ]; then
    _e2e_exec "$CC" run "$src" -- "$long_arg" "$5" >/dev/null 2>&1; got=$?
  else
    _e2e_exec "$CC" run "$src" -- "$long_arg" >/dev/null 2>&1; got=$?
  fi
  if _e2e_runtime_failure "cli_run_$1" "$got"; then return; fi
  if [ "$got" = "$4" ]; then echo "ok   cli_run_$1: complete argv across read chunk"; else echo "FAIL cli_run_$1: got $got want $4"; fail=1; fi
}

# FFI (spec 150 §FN-9, C-ABI foreign calls): link an Alatyr program `test/ffi/<name>.al` against a
# PURE-ARITHMETIC C stub `test/ffi/<name>.c` (no libc). The C stub compiles to an object (`cc -c`);
# the Alatyr program emits GAS ("$CC test/ffi/<name>.al" to stdout), assembles (`as`), and BOTH
# objects link with `ld` (the Alatyr program provides its own `_start` and exits via raw syscall, so
# no libc/crt is needed as long as the stub is pure arithmetic). Run the binary, check the exit code.
# x86_64-ONLY (the C ABI is arch-specific) — named `run_ffi`, so NOT matched by the sweeps' `^run
# [a-z]` grep. Requires `cc` (stdenv, in the nix devShell); if absent, SKIPS (an env gap is not a
# test failure).
run_ffi() { # name, want
  command -v cc >/dev/null 2>&1 || { echo "skip $1(ffi): cc absent"; return; }
  src="$E2E_TEST/ffi/$1.al"; cstub="$E2E_TEST/ffi/$1.c"
  [ -f "$src" ] || { echo "MISS $1(ffi): no $src"; fail=1; return; }
  [ -f "$cstub" ] || { echo "MISS $1(ffi): no $cstub"; fail=1; return; }
  cobj="$T/e2e_ffi_$1_c.o"; asm="$T/e2e_ffi_$1.s"
  alobj="$T/e2e_ffi_$1_al.o"; bin="$T/e2e_ffi_$1.bin"
  # -fno-stack-protector: the stubs link against NO libc, so a stack canary's `__stack_chk_fail` ref
  # would be an undefined symbol at `ld` (a struct-returning stub trips the canary on some toolchains).
  cc -fno-stack-protector -c -o "$cobj" "$cstub" >/dev/null 2>&1 || { echo "FAIL $1(ffi): cc -c"; fail=1; return; }
  "$CC" "$src" > "$asm" 2>/dev/null || { echo "FAIL $1(ffi): emit"; fail=1; return; }
  as "$asm" -o "$alobj" >/dev/null 2>&1 || { echo "FAIL $1(ffi): as"; fail=1; return; }
  ld "$alobj" "$cobj" -o "$bin" >/dev/null 2>&1 || { echo "FAIL $1(ffi): ld"; fail=1; return; }
  _e2e_exec "$bin" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "$1(ffi)" "$got"; then return; fi
  if [ "$got" = "$2" ]; then echo "ok   $1(ffi): $got"; else echo "FAIL $1(ffi): got $got want $2"; fail=1; fi
}

# MOD-9 (Modules §7.5 / Manifest appendix §3.5) — manifest-driven foreign-library LINKING via a
# package's `libs`/`linker_flags`. `run_link`: a package that opts a library into DYNAMIC linking
# (`Lib(name=…, link=LinkMode.dynamic)`) → the toolchain links it with `cc -nostartfiles <obj> -o
# <out> -l<name>` (dynamic PIE, keeps the program's own `_start`); the committed `test/link/<name>/`
# {package.al,src/main.al} call libm `sqrt`. `run_link_static`: the HERMETIC-STATIC default — a C stub is
# compiled to a LOCAL `.a` archive and absorbed by `ld -static <obj> -o <out> -L<dir> -l<name>` (this
# nix env has no system static libs on cc's default path); the package.al is GENERATED with the
# archive's absolute dir (machine-specific → gitignored). x86_64-only. SKIPS when cc / ar is absent
# (an env gap is not a test failure). `run_link*` is NOT matched by the sweeps' `^run [a-z]` grep.
run_link() { # name, want   (DYNAMIC: committed package.al, -l<name> via cc)
  command -v cc >/dev/null 2>&1 || { echo "skip $1(link): cc absent"; return; }
  pkg="$(_fixture_tree link)/$1/package.al"
  [ -f "$pkg" ] || { echo "MISS $1(link): no $pkg"; fail=1; return; }
  "$CC" build "$pkg" >/dev/null 2>&1 || { echo "FAIL $1(link): build"; fail=1; return; }
  bin="$(_fixture_tree link)/$1/target/debug/$1"
  [ -x "$bin" ] || { echo "FAIL $1(link): no artifact $bin"; fail=1; return; }
  _e2e_exec "$bin" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "$1(link)" "$got"; then return; fi
  if [ "$got" = "$2" ]; then echo "ok   $1(link): $got"; else echo "FAIL $1(link): got $got want $2"; fail=1; fi
}

run_link_static() { # name, want   (STATIC: local .a archive absorbed by ld -static -L<dir>)
  command -v cc >/dev/null 2>&1 && command -v ar >/dev/null 2>&1 || { echo "skip $1(link-static): cc/ar absent"; return; }
  d="$(_fixture_tree link)/$1"
  [ -f "$d/stub.c" ] || { echo "MISS $1(link-static): no $d/stub.c"; fail=1; return; }
  [ -f "$d/src/main.al" ] || { echo "MISS $1(link-static): no $d/src/main.al"; fail=1; return; }
  cc -fno-stack-protector -c -o "$d/stub.o" "$d/stub.c" >/dev/null 2>&1 || { echo "FAIL $1(link-static): cc -c"; fail=1; return; }
  ar rcs "$d/libstub.a" "$d/stub.o" >/dev/null 2>&1 || { echo "FAIL $1(link-static): ar"; fail=1; return; }
  # package.al carries the archive's ABSOLUTE dir (machine-specific) — generated here, gitignored.
  cat > "$d/package.al" <<EOF
app := Package(
    version = "0.1.0",
    target_dir = "target",
    libs = [
        Lib(name = "stub"),
    ],
    linker_flags = ["-L$d"],
    targets = [
        Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf, entry = "_start", output = "$1"),
    ]
)
EOF
  "$CC" build "$d/package.al" >/dev/null 2>&1 || { echo "FAIL $1(link-static): build"; fail=1; return; }
  bin="$d/target/debug/$1"
  [ -x "$bin" ] || { echo "FAIL $1(link-static): no artifact $bin"; fail=1; return; }
  _e2e_exec "$bin" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "$1(link-static)" "$got"; then return; fi
  if [ "$got" = "$2" ]; then echo "ok   $1(link-static): $got"; else echo "FAIL $1(link-static): got $got want $2"; fail=1; fi
}

# Tooling §2.2 / Manifest §3.2 — non-executable package artifacts. `object` stops after `as`;
# `static_lib` archives that same deterministic object with `ar`. Both artifacts must retain the
# public API plus its private transitive helper, omit the package's private `main`, keep private code
# and immutable table storage local/read-only, and link an external Alatyr consumer through the exact
# module-qualified public symbol.
run_library_target() { # package name, kind, expected exit
  command -v as >/dev/null 2>&1 && command -v ld >/dev/null 2>&1 && command -v nm >/dev/null 2>&1 && command -v readelf >/dev/null 2>&1 || { echo "skip $1($2): as/ld/nm/readelf absent"; return; }
  if [ "$2" = "static_lib" ]; then
    command -v ar >/dev/null 2>&1 || { echo "skip $1($2): ar absent"; return; }
  fi
  _lt="$(_fixture_tree link)/$1"
  if [ "$2" = "static_lib" ]; then artifact="$_lt/target/debug/libanswer.a"; else artifact="$_lt/target/debug/libanswer.o"; fi
  pkg="$_lt/package.al"
  "$CC" build "$pkg" >/dev/null 2>&1 || { echo "FAIL $1($2): build"; fail=1; return; }
  [ -f "$artifact" ] || { echo "FAIL $1($2): no artifact $artifact"; fail=1; return; }
  nm "$artifact" 2>/dev/null | grep -qE ' T codec__answer$' || { echo "FAIL $1($2): public API symbol missing"; fail=1; return; }
  nm "$artifact" 2>/dev/null | grep -qE ' t codec__helper$' || { echo "FAIL $1($2): private text helper is not local"; fail=1; return; }
  nm "$artifact" 2>/dev/null | grep -qE ' t codec__leaf$' || { echo "FAIL $1($2): private scalar-leaf helper is not local"; fail=1; return; }
  nm "$artifact" 2>/dev/null | grep -qE ' r codec__TABLE$' || { echo "FAIL $1($2): immutable private table is not local read-only data"; fail=1; return; }
  if nm -g "$artifact" 2>/dev/null | grep -qE ' codec__(helper|leaf|TABLE)$'; then
    echo "FAIL $1($2): private implementation symbol leaked globally"; fail=1; return
  fi
  readelf -sW "$artifact" 2>/dev/null | grep -qE 'LOCAL.*codec__helper$' || { echo "FAIL $1($2): helper ELF binding is not local"; fail=1; return; }
  readelf -sW "$artifact" 2>/dev/null | grep -qE 'LOCAL.*codec__leaf$' || { echo "FAIL $1($2): scalar-leaf ELF binding is not local"; fail=1; return; }
  readelf -sW "$artifact" 2>/dev/null | grep -qE 'LOCAL.*codec__TABLE$' || { echo "FAIL $1($2): table ELF binding is not local"; fail=1; return; }
  if nm "$artifact" 2>/dev/null | grep -qE ' T codec__main$'; then
    echo "FAIL $1($2): executable main leaked into library artifact"; fail=1; return
  fi
  consumer="$E2E_TEST/link/library_consumer.al"
  gas="$T/e2e_$1_consumer.s"
  obj="$T/e2e_$1_consumer.o"
  bin="$T/e2e_$1_consumer.bin"
  "$CC" "$consumer" > "$gas" 2>/dev/null || { echo "FAIL $1($2): consumer emit"; fail=1; return; }
  as "$gas" -o "$obj" >/dev/null 2>&1 || { echo "FAIL $1($2): consumer assemble"; fail=1; return; }
  ld "$obj" "$artifact" -o "$bin" >/dev/null 2>&1 || { echo "FAIL $1($2): consumer link"; fail=1; return; }
  _e2e_exec "$bin" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "$1($2)" "$got"; then return; fi
  if [ "$got" = "$3" ]; then echo "ok   $1($2): $got"; else echo "FAIL $1($2): got $got want $3"; fail=1; fi
}

# TOOL-5 production boundary — the normal build may parse @test declarations but must not emit their
# bodies. The dedicated `test` path is exercised by the native_test_runner checks below; this probe
# locks the complementary nm surface on a production executable.
production_test_dce() {
  src="$E2E_TEST/package/tool5_contract/src/main.al"
  out="$T/e2e_tool5_production"
  "$CC" -o "$out" "$src" >/dev/null 2>&1 || { echo "FAIL production_test_dce: build"; fail=1; return; }
  if nm "$out" 2>/dev/null | grep -qE '__test|test[0-9]'; then
    echo "FAIL production_test_dce: @test body leaked into executable"; fail=1
  else
    echo "ok   production_test_dce: production executable omits @test bodies"
  fi
}

# Production reachability for bodyless @abi(syscall) declarations: a retained API call keeps its
# private local trampoline in both the inspectable object and the static archive, while a declaration
# referenced only by an @test body is absent from both. The dedicated test artifact must still link
# and run the test-only syscall, proving TOOL-5 roots retain its kind-4 declaration.
abi_reachability_dce() {
  p="$(_fixture_tree package)/abi_reachability"
archive="$p/target/debug/libabi-reachability.a"
  object="$archive.o"
  ( cd "$p" && "$CC" build package.al ) >/dev/null 2>&1 || { echo "FAIL abi_reachability_dce: build"; fail=1; return; }
  for artifact in "$object" "$archive"; do
    [ -f "$artifact" ] || { echo "FAIL abi_reachability_dce: missing $artifact"; fail=1; continue; }
    nm "$artifact" 2>/dev/null | grep -qE ' t std__os__sys_mmap$' || { echo "FAIL abi_reachability_dce: retained qualified @abi is missing or not local in $artifact"; fail=1; }
    if nm -g "$artifact" 2>/dev/null | grep -qE ' std__os__sys_mmap$'; then
      echo "FAIL abi_reachability_dce: private retained @abi leaked globally into $artifact"
      fail=1
    fi
    if nm "$artifact" 2>/dev/null | grep -qE ' [Tt] main__sys_mmap$'; then
      echo "FAIL abi_reachability_dce: test-only @abi leaked into $artifact"
      fail=1
    else
      echo "ok   abi_reachability_dce: test-only @abi omitted from $(basename "$artifact")"
    fi
  done
  report_file="$T/abi_reachability.test.out"
  _e2e_exec_capture_combined "$report_file" "$CC" test -k "$p/package.al"; got=$?
  report="$(<"$report_file")"
  if _e2e_runtime_failure "abi_reachability_dce(test)" "$got"; then return; fi
  if [ "$got" = 0 ] && case "$report" in *"test test-only abi remains in dedicated test artifact: ok"*) true ;; *) false ;; esac; then
    echo "ok   abi_reachability_dce: dedicated test retains and runs test-only @abi"
  else
    echo "FAIL abi_reachability_dce: test rc=$got output=$report"
    fail=1
  fi
}

# Proposal #11 / Tooling §2.2 — a static library's root set is the package's public API, not every
# `pub` helper in the injected `base`/`alloc`/`std` modules. The fixture's excluded `main` calls
# `std::io::print`; the archive must still contain exactly one text symbol, `lib__go`.
library_dce_scope() {
  p="$(_fixture_tree package)/library_dce_scope"
archive="$p/target/debug/library-dce-scope.a"
  ( cd "$p" && "$CC" check package.al ) >/dev/null 2>&1 || { echo "FAIL library_dce_scope: check"; fail=1; return; }
  ( cd "$p" && "$CC" build package.al ) >/dev/null 2>&1 || { echo "FAIL library_dce_scope: build"; fail=1; return; }
  [ -f "$archive" ] || { echo "FAIL library_dce_scope: missing archive"; fail=1; return; }
  nm_out="$(nm "$archive" 2>/dev/null)" || { echo "FAIL library_dce_scope: nm"; fail=1; return; }
  text_symbols="$(printf '%s\n' "$nm_out" | awk '$2 == "T" { print $3 }')"
  text_count="$(printf '%s\n' "$text_symbols" | awk 'NF { n++ } END { print n + 0 }')"
  if [ "$text_count" = 1 ] && [ "$text_symbols" = "lib__go" ]; then
    echo "ok   library_dce_scope: 1/1 text symbol (lib__go)"
  else
    echo "FAIL library_dce_scope: got $text_count text symbols: $text_symbols"
    fail=1
  fi
}

# (WASM→WAT): emit `test/<name>.al` to WAT, assemble with wat2wasm (structural + type
# validation), run under wasmtime, check the exit code. Requires wat2wasm + wasmtime (flake
# devShell); if either is absent this SKIPS (an env gap is not a test failure) but says so.
run_wat() { # name, want
  command -v wat2wasm >/dev/null 2>&1 && command -v wasmtime >/dev/null 2>&1 || { echo "skip $1: wat2wasm/wasmtime absent"; return; }
  src="$E2E_TEST/$1.al"
  [ -f "$src" ] || { echo "MISS $1: no $src"; fail=1; return; }
  wat="$T/e2e_$1.wat"; wasm="$T/e2e_$1.wasm"
  "$CC" wat "$src" > "$wat" 2>/dev/null || { echo "FAIL $1(wat): emit"; fail=1; return; }
  wat2wasm "$wat" -o "$wasm" 2>/dev/null || { echo "FAIL $1(wat): wat2wasm"; fail=1; return; }
  _e2e_exec wasmtime "$wasm" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "$1(wat)" "$got"; then return; fi
  if [ "$got" = "$2" ]; then echo "ok   $1(wat): $got"; else echo "FAIL $1(wat): got $got want $2"; fail=1; fi
}

# WASM print: emit to WAT, run under wasmtime, check BOTH captured stdout and exit code
# (a print program's output is its point). want-out uses $'\n' for newlines. Soft-skips.
run_wat_out() { # name, want-out, want-exit
  command -v wat2wasm >/dev/null 2>&1 && command -v wasmtime >/dev/null 2>&1 || { echo "skip $1: wat2wasm/wasmtime absent"; return; }
  src="$E2E_TEST/$1.al"
  [ -f "$src" ] || { echo "MISS $1: no $src"; fail=1; return; }
  wat="$T/e2e_$1.wat"; wasm="$T/e2e_$1.wasm"
  "$CC" wat "$src" > "$wat" 2>/dev/null || { echo "FAIL $1(wat-out): emit"; fail=1; return; }
  wat2wasm "$wat" -o "$wasm" 2>/dev/null || { echo "FAIL $1(wat-out): wat2wasm"; fail=1; return; }
  _e2e_exec_capture "$T/e2e_$1.wat.stdout" wasmtime "$wasm" 2>/dev/null; ec=$?
  got="$(<"$T/e2e_$1.wat.stdout")"
  if _e2e_runtime_failure "$1(wat-out)" "$ec"; then return; fi
  if [ "$got" = "$2" ] && [ "$ec" = "$3" ]; then echo "ok   $1(wat-out): out+exit"; else echo "FAIL $1(wat-out): out=[$got] exit=$ec want=[$2]/$3"; fail=1; fi
}

# MOD §6.3/§7.2 (WAT @export/@extern): emit `test/<name>.al` to WAT, assert wat2wasm ACCEPTS it
# (the module is structurally valid) AND that the emitted WAT contains the fixed string $2 (the
# `(export "…"` entry or the `(import "env" "…"` FFI import). Does NOT run it — an @extern's host
# import is unsatisfied under wasmtime, so this checks emission fidelity, not execution. Soft-skips
# when wat2wasm is absent (checks nothing but the emit then).
check_wat_has() { # name, needle
  src="$E2E_TEST/$1.al"
  [ -f "$src" ] || { echo "MISS $1: no $src"; fail=1; return; }
  wat="$T/e2e_$1.wat"
  "$CC" wat "$src" > "$wat" 2>/dev/null || { echo "FAIL $1(wat-has): emit"; fail=1; return; }
  if ! grep -qF "$2" "$wat"; then echo "FAIL $1(wat-has): missing [$2]"; fail=1; return; fi
  if command -v wat2wasm >/dev/null 2>&1; then
    wat2wasm "$wat" -o "$T/e2e_$1.wasm" 2>/dev/null || { echo "FAIL $1(wat-has): wat2wasm rejected a valid module"; fail=1; return; }
  fi
  echo "ok   $1(wat-has): [$2]"
}

# backend emission must be reproducible even when the AST arena moves between
# processes. Loop/control-flow labels are an implementation detail, but pointer-derived names make
# byte comparison (and any future content-addressed cache) meaningless. Run both a While and a Loop
# shape twice for each affected backend and require byte-identical output.
check_backend_determinism() {
  for backend in riscv64 wat; do
    for name in wasm_loop_sum loop_expr_labels; do
      src="$E2E_TEST/$name.al"
      a="$T/determinism_${backend}_${name}.a"
      b="$T/determinism_${backend}_${name}.b"
      [ -f "$src" ] || { echo "MISS $name: no $src"; fail=1; continue; }
      "$CC" "$backend" "$src" > "$a" 2>/dev/null || { echo "FAIL $backend/$name: first emit"; fail=1; continue; }
      "$CC" "$backend" "$src" > "$b" 2>/dev/null || { echo "FAIL $backend/$name: second emit"; fail=1; continue; }
      if cmp -s "$a" "$b"; then
        echo "ok   $backend/$name: deterministic emit"
      else
        echo "FAIL $backend/$name: nondeterministic emit"
        fail=1
      fi
    done
  done
}

# Modules §4.3 — ordinary one-hop module re-export. The source keeps `facade` and the entry module
# in one focused front-end input so the non-x86 resolver sees `pub math := std::math`; the check is
# structural because the WAT backend is the consumer of driver::d_qual_target. A missing rewrite
# leaves the qualified callee unresolved and emits the existing trap path instead of `$floor`.
check_reexport_wat() {
  src="$E2E_TEST/import_reexport.al"
  [ -f "$src" ] || { echo "MISS import_reexport: no $src"; fail=1; return; }
  wat="$T/e2e_import_reexport.wat"
  "$CC" wat "$src" > "$wat" 2>/dev/null || { echo "FAIL import_reexport(wat): emit"; fail=1; return; }
  grep -qF '(call $floor ' "$wat" || { echo "FAIL import_reexport(wat): re-export call was not normalized to $floor"; fail=1; return; }
  echo "ok   import_reexport(wat): one pub module re-export reaches floor"
}

# (aarch64): emit `test/<name>.al` to AArch64 GAS, assemble+link with the cross binutils
# (aarch64-unknown-linux-gnu-{as,ld}), run under qemu-aarch64, check the exit code — the same verify
# loop as the native x86_64 / wasmtime paths. Requires the cross toolchain + qemu-aarch64 (flake
# devShell); if absent this SKIPS (an env gap is not a failure) but says so.
run_a64() { # name, want
  command -v aarch64-unknown-linux-gnu-as >/dev/null 2>&1 && command -v qemu-aarch64 >/dev/null 2>&1 || { echo "skip $1: aarch64 toolchain absent"; return; }
  src="$E2E_TEST/$1.al"
  [ -f "$src" ] || { echo "MISS $1: no $src"; fail=1; return; }
  s="$T/e2e_$1.s"; o="$T/e2e_$1.o"; elf="$T/e2e_$1.elf"
  "$CC" aarch64 "$src" > "$s" 2>/dev/null || { echo "FAIL $1(a64): emit"; fail=1; return; }
  aarch64-unknown-linux-gnu-as "$s" -o "$o" 2>/dev/null || { echo "FAIL $1(a64): as"; fail=1; return; }
  aarch64-unknown-linux-gnu-ld "$o" -o "$elf" 2>/dev/null || { echo "FAIL $1(a64): ld"; fail=1; return; }
  _e2e_exec qemu-aarch64 "$elf" >/dev/null 2>&1; got=$?   # ulimit -c 0 is set in the prologue; a brk trap must not dump a core
  if _e2e_runtime_failure "$1(a64)" "$got"; then return; fi
  if [ "$got" = "$2" ]; then echo "ok   $1(a64): $got"; else echo "FAIL $1(a64): got $got want $2"; fail=1; fi
}

# Issue #41 / Modules §6.1–§7.2 — a qualified AArch64 call must execute and its named, non-generic
# definitions must carry their module-qualified labels. The symbol arguments are deliberately not
# searched in the fixture comments: this assertion reads the linked ELF produced from the emitted GAS.
run_a64_symbols() { # name, want, symbol…
  command -v aarch64-unknown-linux-gnu-as >/dev/null 2>&1 && command -v aarch64-unknown-linux-gnu-ld >/dev/null 2>&1 \
    && command -v qemu-aarch64 >/dev/null 2>&1 && command -v nm >/dev/null 2>&1 \
    || { echo "skip $1(a64-symbols): aarch64 toolchain or nm absent"; return; }
  local name="$1" want="$2"; shift 2
  local src="$E2E_TEST/$name.al"
  [ -f "$src" ] || { echo "MISS $name(a64-symbols): no $src"; fail=1; return; }
  local s="$T/e2e_$name.symbols.s" o="$T/e2e_$name.symbols.o" elf="$T/e2e_$name.symbols.elf" nmout="$T/e2e_$name.symbols.nm"
  "$CC" aarch64 "$src" > "$s" 2>/dev/null || { echo "FAIL $name(a64-symbols): emit"; fail=1; return; }
  aarch64-unknown-linux-gnu-as "$s" -o "$o" 2>/dev/null || { echo "FAIL $name(a64-symbols): as"; fail=1; return; }
  aarch64-unknown-linux-gnu-ld "$o" -o "$elf" 2>/dev/null || { echo "FAIL $name(a64-symbols): ld"; fail=1; return; }
  _e2e_exec qemu-aarch64 "$elf" >/dev/null 2>&1; local got=$?
  if [ "$got" != "$want" ]; then echo "FAIL $name(a64-symbols): got $got want $want"; fail=1; return; fi
  nm "$elf" > "$nmout" 2>/dev/null || { echo "FAIL $name(a64-symbols): nm"; fail=1; return; }
  local symbol missing=0
  for symbol in "$@"; do
    if ! grep -qE " [tT] $symbol$" "$nmout"; then
      echo "FAIL $name(a64-symbols): missing $symbol"
      missing=1
    fi
  done
  if [ "$missing" = 0 ]; then echo "ok   $name(a64-symbols): $got + nm $# module-qualified symbols"; else fail=1; fi
}

# §8.2 aarch64 print: emit, assemble+link, run under qemu-aarch64, check BOTH stdout and exit code.
run_a64_out() { # name, want-out, want-exit
  command -v aarch64-unknown-linux-gnu-as >/dev/null 2>&1 && command -v qemu-aarch64 >/dev/null 2>&1 || { echo "skip $1: aarch64 toolchain absent"; return; }
  src="$E2E_TEST/$1.al"
  [ -f "$src" ] || { echo "MISS $1: no $src"; fail=1; return; }
  s="$T/e2e_$1.s"; o="$T/e2e_$1.o"; elf="$T/e2e_$1.elf"
  "$CC" aarch64 "$src" > "$s" 2>/dev/null || { echo "FAIL $1(a64-out): emit"; fail=1; return; }
  aarch64-unknown-linux-gnu-as "$s" -o "$o" 2>/dev/null || { echo "FAIL $1(a64-out): as"; fail=1; return; }
  aarch64-unknown-linux-gnu-ld "$o" -o "$elf" 2>/dev/null || { echo "FAIL $1(a64-out): ld"; fail=1; return; }
  _e2e_exec_capture "$T/e2e_$1.a64.stdout" qemu-aarch64 "$elf" 2>/dev/null; ec=$?   # ulimit -c 0: no core litter on a trap
  got="$(<"$T/e2e_$1.a64.stdout")"
  if _e2e_runtime_failure "$1(a64-out)" "$ec"; then return; fi
  if [ "$got" = "$2" ] && [ "$ec" = "$3" ]; then echo "ok   $1(a64-out): out+exit"; else echo "FAIL $1(a64-out): out=[$got] exit=$ec want=[$2]/$3"; fail=1; fi
}

# (riscv64): emit `test/<name>.al` to RISC-V64 GAS, assemble+link with the cross binutils
# (riscv64-unknown-linux-gnu-{as,ld}), run under qemu-riscv64, check the exit code. SKIPS if the cross
# toolchain + qemu-riscv64 are absent. ulimit -c 0 so an ebreak trap dumps no core into the repo.
run_rv64() { # name, want
  command -v riscv64-unknown-linux-gnu-as >/dev/null 2>&1 && command -v qemu-riscv64 >/dev/null 2>&1 || { echo "skip $1: riscv64 toolchain absent"; return; }
  src="$E2E_TEST/$1.al"
  [ -f "$src" ] || { echo "MISS $1: no $src"; fail=1; return; }
  s="$T/e2e_rv_$1.s"; o="$T/e2e_rv_$1.o"; elf="$T/e2e_rv_$1.elf"
  "$CC" riscv64 "$src" > "$s" 2>/dev/null || { echo "FAIL $1(rv64): emit"; fail=1; return; }
  riscv64-unknown-linux-gnu-as "$s" -o "$o" 2>/dev/null || { echo "FAIL $1(rv64): as"; fail=1; return; }
  riscv64-unknown-linux-gnu-ld "$o" -o "$elf" 2>/dev/null || { echo "FAIL $1(rv64): ld"; fail=1; return; }
  _e2e_exec qemu-riscv64 "$elf" >/dev/null 2>&1
  got=$?
  if _e2e_runtime_failure "$1(rv64)" "$got"; then return; fi
  if [ "$got" = "$2" ]; then echo "ok   $1(rv64): $got"; else echo "FAIL $1(rv64): got $got want $2"; fail=1; fi
}

# §8.3 riscv64 print: run under qemu-riscv64, check BOTH stdout and exit code.
run_rv64_out() { # name, want-out, want-exit
  command -v riscv64-unknown-linux-gnu-as >/dev/null 2>&1 && command -v qemu-riscv64 >/dev/null 2>&1 || { echo "skip $1: riscv64 toolchain absent"; return; }
  src="$E2E_TEST/$1.al"
  [ -f "$src" ] || { echo "MISS $1: no $src"; fail=1; return; }
  s="$T/e2e_rv_$1.s"; o="$T/e2e_rv_$1.o"; elf="$T/e2e_rv_$1.elf"
  "$CC" riscv64 "$src" > "$s" 2>/dev/null || { echo "FAIL $1(rv64-out): emit"; fail=1; return; }
  riscv64-unknown-linux-gnu-as "$s" -o "$o" 2>/dev/null || { echo "FAIL $1(rv64-out): as"; fail=1; return; }
  riscv64-unknown-linux-gnu-ld "$o" -o "$elf" 2>/dev/null || { echo "FAIL $1(rv64-out): ld"; fail=1; return; }
  _e2e_exec_capture "$T/e2e_$1.rv64.stdout" qemu-riscv64 "$elf" 2>/dev/null; ec=$?
  got="$(<"$T/e2e_$1.rv64.stdout")"
  if _e2e_runtime_failure "$1(rv64-out)" "$ec"; then return; fi
  if [ "$got" = "$2" ] && [ "$ec" = "$3" ]; then echo "ok   $1(rv64-out): out+exit"; else echo "FAIL $1(rv64-out): out=[$got] exit=$ec want=[$2]/$3"; fail=1; fi
}

check_reject() { # name
  src="$E2E_TEST/$1.al"
  [ -f "$src" ] || { echo "MISS $1: no $src"; fail=1; return; }
  "$CC" check "$src" >/dev/null 2>&1; got=$?
  if [ "$got" = 1 ]; then echo "ok   $1: rejected"; else echo "FAIL $1: check rc=$got want 1"; fail=1; fi
}

# Assert the CHECK-path diagnostic as well as its non-zero verdict. This is the check-subcommand twin
# of `build_reject_has`; a shared pre-emission fence must not only reject but retain its source location
# and intended wording on the type-check-only surface.
check_reject_has() { # name, needle
  src="$E2E_TEST/$1.al"
  [ -f "$src" ] || { echo "MISS $1: no $src"; fail=1; return; }
  out="$T/e2e_$1.checkout"; err="$T/e2e_$1.checkerr"
  "$CC" check "$src" >"$out" 2>"$err"; got=$?
  if [ "$got" = 0 ]; then echo "FAIL $1: check accepted, want a located reject"; fail=1; return; fi
  if [ -s "$out" ]; then echo "FAIL $1: check rc=$got but $(wc -c < "$out") bytes reached stdout"; fail=1; return; fi
  if grep -qF "$2" "$err"; then echo "ok   $1: check rejected with the diagnostic"
  else echo "FAIL $1: check rc=$got but the diagnostic is missing [$2]"; fail=1; fi
}

check_accept() { # name
  src="$E2E_TEST/$1.al"
  [ -f "$src" ] || { echo "MISS $1: no $src"; fail=1; return; }
  "$CC" check "$src" >/dev/null 2>&1; got=$?
  if [ "$got" = 0 ]; then echo "ok   $1: accepted"; else echo "FAIL $1: check rc=$got want 0"; fail=1; fi
}

# Assert the BUILD (lower) FAILS LOUD — for a construct the lean lower rejects with a panic that sema
# (`check`) does not model, so it can't use check_reject. A non-zero build rc = the fail-loud we want
# (the alternative, a valid binary with a wrong result, would be the forbidden silent miscompile).
build_reject() { # name
  src="$E2E_TEST/$1.al"
  [ -f "$src" ] || { echo "MISS $1: no $src"; fail=1; return; }
  out="$T/e2e_$1.out"
  "$CC" -o "$out" "$src" >/dev/null 2>&1; got=$?
  if [ "$got" = 0 ]; then echo "FAIL $1: build succeeded, want fail-loud"; fail=1; return; fi
  if [ -e "$out" ]; then echo "FAIL $1: rejected but left an output artifact"; fail=1; return; fi
  echo "ok   $1: build rejected"
}

# Assert the BUILD fails with a SPECIFIC diagnostic — stronger than `build_reject`, which a fail-loud
# ACCIDENT also satisfies: before `require_reservation`, `reject_narrow_slot_rebind` killed the compiler
# with an internal overflow trap (SIGILL, core dumped, EMPTY stderr) and a bare `build_reject` would have
# called that a pass. The needle is what gives such a fixture teeth.
# The three EMIT-to-stdout surfaces (`alatyr wat|aarch64|riscv64 <file>`) must run the same check the `-o`
# build path runs BEFORE emitting: an ill-typed program must exit non-zero with the SAME located
# `alatyr: check: …` diagnostic and emit NOTHING. Measured before that landed, these surfaces exited 0 and
# printed 34/44/54 lines of code for a program `-o` rejects — three of the four emit entry points handing a
# user machine code for a program the compiler knows is wrong. All three facts are asserted separately: a
# bare non-zero exit is also what a crash gives, and a non-zero exit after a partial emit would still have
# leaked code to stdout. No existing helper can express this: `run_wat`/`check_wat_has` treat a non-zero emit
# as a HARNESS failure, `build_reject*` drives `-o`, and `check_reject` drives `check`.
emit_reject_has() { # backend, name, needle
  src="$E2E_TEST/$2.al"
  [ -f "$src" ] || { echo "MISS $2: no $src"; fail=1; return; }
  out="$T/e2e_$2.$1.emit"; err="$T/e2e_$2.$1.emiterr"
  "$CC" "$1" "$src" > "$out" 2>"$err"; got=$?
  if [ "$got" = 0 ]; then echo "FAIL $2($1-reject): exit 0 with $(wc -c < "$out") bytes emitted, want a located reject"; fail=1; return; fi
  if [ -s "$out" ]; then echo "FAIL $2($1-reject): rc=$got but $(wc -c < "$out") bytes reached stdout"; fail=1; return; fi
  if ! grep -qF "$3" "$err"; then echo "FAIL $2($1-reject): rc=$got, nothing emitted, but the diagnostic is missing [$3]"; fail=1; return; fi
  echo "ok   $2($1-reject): rejected, nothing emitted"
}

build_reject_has() { # name, needle
  src="$E2E_TEST/$1.al"
  [ -f "$src" ] || { echo "MISS $1: no $src"; fail=1; return; }
  key="${1//\//_}"
  out="$T/e2e_$key.out"
  err="$T/e2e_$key.err"
  "$CC" -o "$out" "$src" >/dev/null 2>"$err"; got=$?
  if [ "$got" = 0 ]; then echo "FAIL $1: build succeeded, want a located reject"; fail=1; return; fi
  if [ -e "$out" ]; then echo "FAIL $1: rejected but left an output artifact"; fail=1; return; fi
  if grep -qF "$2" "$err"; then echo "ok   $1: build rejected with the diagnostic"
  else echo "FAIL $1: rc=$got but the diagnostic is missing [$2]"; fail=1; fi
}

# Issue #174 / Declarations §1.2 + Grammar §3.1 — every value expression is name-checked even when
# its result is discarded, and a known struct's field name is checked on both reads and writes. The
# sources are generated in this row's private scratch directory so the regression does not add rows to
# the four-backend corpus oracle. Each negative case proves check/build parity, a located diagnostic, and
# no output artifact; the positive cases preserve valid pointless expressions and the corresponding good
# names. This is intentionally stronger than a bare non-zero assertion: a crash or a partial build is not
# a semantic refusal.
issue174_name_resolution_test() {
  d="$T/issue174_name_resolution"
  mkdir -p "$d"
  printf '%s\n' \
    'main := fn() -> u64 {' \
    '  mut count : u64 = 0' \
    '  cout = 5' \
    '  return count' \
    '}' > "$d/assignment.al"
  printf '%s\n' \
    'S := struct {' \
    '  a : u64' \
    '}' \
    'main := fn() -> u64 {' \
    '  s := S(a = 7)' \
    '  return s.nope' \
    '}' > "$d/field_read.al"
  printf '%s\n' \
    'S := struct {' \
    '  a : u64' \
    '}' \
    'main := fn() -> u64 {' \
    '  mut s := S(a = 0)' \
    '  s.nope = 5' \
    '  return s.a' \
    '}' > "$d/field_write.al"
  printf '%s\n' \
    'main := fn() -> u64 {' \
    '  if missing_condition { return 1 }' \
    '  return 42' \
    '}' > "$d/condition.al"
  printf '%s\n' \
    'main := fn() -> u64 {' \
    '  foo()' \
    '  return 42' \
    '}' > "$d/call.al"
  printf '%s\n' \
    'main := fn() -> u64 {' \
    '  missing_name' \
    '  return 42' \
    '}' > "$d/bare.al"
  printf '%s\n' \
    'main := fn() -> u64 {' \
    '  mut count : u64 = 0' \
    '  count = 5' \
    '  return count' \
    '}' > "$d/assignment_ok.al"
  printf '%s\n' \
    'S := struct { a : u64 }' \
    'main := fn() -> u64 {' \
    '  mut s := S(a = 0)' \
    '  s.a = 5' \
    '  return s.a' \
    '}' > "$d/field_ok.al"
  printf '%s\n' \
    'main := fn() -> u64 {' \
    '  present := true' \
    '  if present { return 42 }' \
    '  return 0' \
    '}' > "$d/condition_ok.al"
  printf '%s\n' \
    'main := fn() -> u64 {' \
    '  value := 7' \
    '  5' \
    '  value' \
    '  return 42' \
    '}' > "$d/pointless_ok.al"

  issue174_reject() { # name, source line
    n="$1"; want_line="$2"; src="$d/$n.al"
    co="$d/$n.check.out"; ce="$d/$n.check.err"
    "$CC" check "$src" >"$co" 2>"$ce"; crc=$?
    if [ "$crc" != 1 ] || [ -s "$co" ] || ! grep -qF "unbound name" "$ce" || ! grep -qF "at line $want_line" "$ce"; then
      echo "FAIL issue174/$n(check): rc=$crc or output/diagnostic mismatch [$(<"$ce")]"; fail=1; return
    fi
    bo="$d/$n.bin"; be="$d/$n.build.err"
    "$CC" -o "$bo" "$src" >"$d/$n.build.out" 2>"$be"; brc=$?
    if [ "$brc" != 1 ] || [ -e "$bo" ] || ! grep -qF "unbound name" "$be" || ! grep -qF "at line $want_line" "$be"; then
      echo "FAIL issue174/$n(build): rc=$brc or artifact/diagnostic mismatch [$(<"$be")]"; fail=1; return
    fi
    echo "ok   issue174/$n: check/build rejected with located unbound-name diagnostic"
  }
  issue174_run() { # name, expected exit
    n="$1"; want="$2"; src="$d/$n.al"; out="$d/$n.bin"
    "$CC" -o "$out" "$src" >"$d/$n.run.out" 2>"$d/$n.run.err" || { echo "FAIL issue174/$n: compile/link"; fail=1; return; }
    _e2e_exec "$out" >/dev/null 2>&1; got=$?
    if _e2e_runtime_failure "issue174/$n" "$got"; then return; fi
    if [ "$got" = "$want" ]; then echo "ok   issue174/$n: $got"; else echo "FAIL issue174/$n: got $got want $want"; fail=1; fi
  }

  issue174_reject assignment 3
  issue174_reject field_read 6
  issue174_reject field_write 6
  issue174_reject condition 2
  issue174_reject call 2
  issue174_reject bare 2
  issue174_run assignment_ok 5
  issue174_run field_ok 5
  issue174_run condition_ok 42
  issue174_run pointless_ok 42
}

## Issue #298 / Declarations §3.1 + Memory §1.6 — path stores must use the root binding's mutability,
## not only the bare-name re-assignment path. These generated fixtures stay in the gate's private scratch
## directory: the five negative forms and one positive control exercise check/build without changing the
## per-file corpus oracle. The negative sources contain no diagnostic wording, so the needle cannot pass
## by matching fixture documentation.
issue298_immutable_places_test() {
  local d="$T/issue298_immutable_places"
  rm -rf "$d"
  mkdir -p "$d" || { echo "FAIL issue298_immutable_places: scratch"; fail=1; return; }
  printf '%s\n' \
    'S := struct {' \
    '  f : u64' \
    '}' \
    'main := fn() -> u64 {' \
    '  s := S(f = 1)' \
    '  s.f = 9' \
    '  return s.f' \
    '}' > "$d/field.al"
  printf '%s\n' \
    'main := fn() -> u64 {' \
    '  a := [1, 2, 3]' \
    '  a[0] = 9' \
    '  return a[0]' \
    '}' > "$d/array.al"
  printf '%s\n' \
    'main := fn() -> u64 {' \
    '  a := [1, 2, 3]' \
    '  s := a[0..3]' \
    '  s[0] = 9' \
    '  return s[0]' \
    '}' > "$d/slice.al"
  printf '%s\n' \
    'G : u64 = 1' \
    'main := fn() -> u64 {' \
    '  G = 9' \
    '  return G' \
    '}' > "$d/global.al"
  printf '%s\n' \
    'Inner := struct { f : u64 }' \
    'Outer := struct { inner : Inner }' \
    'main := fn() -> u64 {' \
    '  s := Outer(inner = Inner(f = 1))' \
    '  s.inner.f = 9' \
    '  return s.inner.f' \
    '}' > "$d/nested.al"
  printf '%s\n' \
    'Inner := struct { f : u64 }' \
    'Outer := struct { inner : Inner }' \
    'mut G : u64 = 1' \
    'main := fn() -> u64 {' \
    '  mut s := Outer(inner = Inner(f = 1))' \
    '  s.inner.f = 9' \
    '  mut a : [u64; 3] = [1, 2, 3]' \
    '  a[0] = 7' \
    '  mut view := a[0..3]' \
    '  view[1] = 6' \
    '  G = 5' \
    '  return s.inner.f + a[0] + view[1] + G' \
    '}' > "$d/mutable.al"
  printf '%s\n' \
    'Inner := struct { f : u64 }' \
    'Outer := struct { inner : Inner }' \
    'main := fn() -> u64 {' \
    '  s : Outer' \
    '  s.inner.f = 9' \
    '  a : [u64; 2]' \
    '  a[0] = 8' \
    '  return s.inner.f + a[0]' \
    '}' > "$d/first_write.al"

  issue298_reject() { # name, source line
    local n="$1" want_line="$2" src="$d/$1.al"
    local co="$d/$1.check.out" ce="$d/$1.check.err"
    "$CC" check "$src" >"$co" 2>"$ce"; crc=$?
    if [ "$crc" != 1 ] || [ -s "$co" ] || ! grep -qF "immutable binding" "$ce" || ! grep -qF "at line $want_line" "$ce"; then
      echo "FAIL issue298/$n(check): rc=$crc or output/diagnostic mismatch [$(<"$ce")]"; fail=1; return
    fi
    local bo="$d/$1.bin" be="$d/$1.build.err"
    "$CC" -o "$bo" "$src" >"$d/$1.build.out" 2>"$be"; brc=$?
    if [ "$brc" != 1 ] || [ -e "$bo" ] || ! grep -qF "immutable binding" "$be" || ! grep -qF "at line $want_line" "$be"; then
      echo "FAIL issue298/$n(build): rc=$brc or artifact/diagnostic mismatch [$(<"$be")]"; fail=1; return
    fi
    echo "ok   issue298/$n: check/build rejected with located immutable-binding diagnostic"
  }
  issue298_reject field 6
  issue298_reject array 3
  issue298_reject slice 4
  issue298_reject global 3
  issue298_reject nested 5

  local src="$d/mutable.al" out="$d/mutable.bin"
  "$CC" check "$src" >/dev/null 2>&1 || { echo "FAIL issue298/mutable: check"; fail=1; return; }
  "$CC" -o "$out" "$src" >/dev/null 2>&1 || { echo "FAIL issue298/mutable: build"; fail=1; return; }
  _e2e_exec "$out" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "issue298/mutable" "$got"; then return; fi
  if [ "$got" = 27 ]; then echo "ok   issue298/mutable: mut field/path/index/slice/global writes run 27"; else echo "FAIL issue298/mutable: got $got want 27"; fail=1; fi

  src="$d/first_write.al"; out="$d/first_write.bin"
  "$CC" check "$src" >/dev/null 2>&1 || { echo "FAIL issue298/first_write: check"; fail=1; return; }
  "$CC" -o "$out" "$src" >/dev/null 2>&1 || { echo "FAIL issue298/first_write: build"; fail=1; return; }
  _e2e_exec "$out" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "issue298/first_write" "$got"; then return; fi
  if [ "$got" = 17 ]; then echo "ok   issue298/first_write: immutable field/index first writes run 17"; else echo "FAIL issue298/first_write: got $got want 17"; fail=1; fi
}

## Issue #299 / Types §4.1 + §5.4 — direct user brands carry nominal identity in sema. These generated
## sources stay in the row's private scratch directory: the negative branch must fail only after the
## resolver stops returning UNKNOWN for the two declared brands, while the same-brand control remains
## accepted. No conversion-lattice, generic-payload, alias, wrapper, lowering, or oracle behavior is
## asserted here.
issue299_brand_identity_test() {
  local d="$T/issue299_brand_identity"
  rm -rf "$d"
  mkdir -p "$d" || { echo "FAIL issue299_brand_identity: scratch"; fail=1; return; }
  printf '%s\n' \
    'A := brand(u64)' \
    'B := brand(u64)' \
    'main := fn() -> u64 {' \
    '  a : A = A(1)' \
    '  b : B = B(2)' \
    '  return if true { a } else { b }' \
    '}' > "$d/sibling.al"
  printf '%s\n' \
    'A := brand(u64)' \
    'main := fn() -> u64 {' \
    '  a : A = A(1)' \
    '  return if true { a } else { a }' \
    '}' > "$d/same.al"

  local src="$d/sibling.al" co="$d/sibling.check.out" ce="$d/sibling.check.err"
  "$CC" check "$src" >"$co" 2>"$ce"; crc=$?
  if [ "$crc" = 0 ] || [ -s "$co" ] || ! grep -qF "type mismatch" "$ce" || ! grep -qF "at line 6" "$ce"; then
    echo "FAIL issue299/sibling(check): rc=$crc or diagnostic mismatch [$(<"$ce")]"; fail=1
  else
    echo "ok   issue299/sibling(check): distinct brands rejected at line 6"
  fi
  local bo="$d/sibling.bin" be="$d/sibling.build.err"
  "$CC" -o "$bo" "$src" >"$d/sibling.build.out" 2>"$be"; brc=$?
  if [ "$brc" = 0 ] || [ -e "$bo" ] || ! grep -qF "type mismatch" "$be" || ! grep -qF "at line 6" "$be"; then
    echo "FAIL issue299/sibling(build): rc=$brc or artifact/diagnostic mismatch [$(<"$be")]"; fail=1
  else
    echo "ok   issue299/sibling(build): distinct brands rejected at line 6 without artifact"
  fi

  src="$d/same.al"; bo="$d/same.bin"
  "$CC" check "$src" >/dev/null 2>"$d/same.check.err"; crc=$?
  "$CC" -o "$bo" "$src" >/dev/null 2>"$d/same.build.err"; brc=$?
  if [ "$crc" != 0 ] || [ "$brc" != 0 ] || [ ! -x "$bo" ]; then
    echo "FAIL issue299/same: check=$crc build=$brc"; fail=1; return
  fi
  _e2e_exec "$bo" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "issue299/same" "$got"; then return; fi
  if [ "$got" = 1 ]; then echo "ok   issue299/same: same brand remains accepted"; else echo "FAIL issue299/same: got $got want 1"; fail=1; fi
}

## Issue #304 / TYP-6 + Types §§4.2–4.3 — direct field and local fixed-array-element stores must
## compare the value with the declared destination type before lower can emit a word-sized store.
## These sources live only in the gate's private scratch directory: each negative case checks both
## semantic entry points, the existing located `type mismatch` wording, and the absence of an output
## artifact. The generated headers deliberately do not quote that needle, so an unfixed compiler cannot
## pass by matching its own fixture documentation. The pinned spec puts bool outside the numeric lattice,
## so both direct bool-to-u64 forms are negative controls for that rule; explicit `u64(bool)` remains
## outside this slice as a conversion-constructor surface.
issue304_place_type_test() {
  local d="$T/issue304_place_type"
  rm -rf "$d"
  mkdir -p "$d" || { echo "FAIL issue304_place_type: scratch"; fail=1; return; }
  printf '%s\n' \
    '## The direct field store used to be accepted and reached emission.' \
    'S := struct { f : u64 }' \
    'main := fn() -> u64 {' \
    '  mut s := S(f = 1)' \
    '  s.f = "text"' \
    '  return s.f' \
    '}' > "$d/field_str.al"
  printf '%s\n' \
    '## The direct local fixed-array element store used to be accepted and reached emission.' \
    'main := fn() -> u64 {' \
    '  mut a : [u64; 2] = [1, 2]' \
    '  a[0] = "text"' \
    '  return a[0]' \
    '}' > "$d/array_str.al"
  printf '%s\n' \
    '## bool is outside the numeric lattice; an implicit store is not a conversion.' \
    'S := struct { f : u64 }' \
    'main := fn() -> u64 {' \
    '  mut s := S(f = 1)' \
    '  s.f = true' \
    '  return s.f' \
    '}' > "$d/field_bool.al"
  printf '%s\n' \
    '## bool is outside the numeric lattice for an array element too.' \
    'main := fn() -> u64 {' \
    '  mut a : [u64; 2] = [1, 2]' \
    '  a[0] = true' \
    '  return a[0]' \
    '}' > "$d/array_bool.al"
  printf '%s\n' \
    '## Existing aggregate-to-scalar rejection remains active on a direct field.' \
    'P := struct { x : u64 }' \
    'S := struct { f : u64 }' \
    'main := fn() -> u64 {' \
    '  mut s := S(f = 1)' \
    '  s.f = P(x = 7)' \
    '  return s.f' \
    '}' > "$d/field_aggregate.al"
  printf '%s\n' \
    '## Existing aggregate-to-scalar rejection remains active on a direct array element.' \
    'P := struct { x : u64 }' \
    'main := fn() -> u64 {' \
    '  mut a : [u64; 2] = [1, 2]' \
    '  a[0] = P(x = 7)' \
    '  return a[0]' \
    '}' > "$d/array_aggregate.al"

  issue304_reject() { # name, source line
    local n="$1" want_line="$2" src="$d/$1.al"
    local needle="type mismatch at line $want_line in $n"
    local co="$d/$1.check.out" ce="$d/$1.check.err"
    "$CC" check "$src" >"$co" 2>"$ce"; crc=$?
    if [ "$crc" != 1 ] || [ -s "$co" ] || [ ! -s "$ce" ] || ! grep -qF "$needle" "$ce"; then
      echo "FAIL issue304/$n(check): rc=$crc or output/diagnostic mismatch [$(<"$ce")]"; fail=1; return
    fi
    local out="$d/$1.out" bo="$d/$1.build.out" be="$d/$1.build.err"
    rm -f "$out"
    "$CC" -o "$out" "$src" >"$bo" 2>"$be"; brc=$?
    if [ "$brc" != 1 ] || [ -e "$out" ] || [ ! -s "$be" ] || ! grep -qF "$needle" "$be"; then
      echo "FAIL issue304/$n(build): rc=$brc or artifact/diagnostic mismatch [$(<"$be")]"; fail=1; return
    fi
    echo "ok   issue304/$n: check/build rejected with located type-mismatch diagnostic and no artifact"
  }
  issue304_reject field_str 5
  issue304_reject array_str 4
  issue304_reject field_bool 5
  issue304_reject array_bool 4
  issue304_reject field_aggregate 6
  issue304_reject array_aggregate 5

  local src="$d/valid.al" out="$d/valid.out"
  printf '%s\n' \
    '## Correct scalar stores through both direct place forms remain valid.' \
    'S := struct { f : u64 }' \
    'main := fn() -> u64 {' \
    '  mut s := S(f = 1)' \
    '  s.f = 40' \
    '  mut a : [u64; 2] = [1, 2]' \
    '  a[0] = 2' \
    '  return s.f + a[0]' \
    '}' > "$src"
  "$CC" check "$src" >/dev/null 2>&1 || { echo "FAIL issue304/valid: check"; fail=1; return; }
  "$CC" -o "$out" "$src" >/dev/null 2>&1 || { echo "FAIL issue304/valid: build"; fail=1; return; }
  _e2e_exec "$out" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "issue304/valid" "$got"; then return; fi
  if [ "$got" = 42 ]; then echo "ok   issue304/valid: field and local array-element stores run 42"; else echo "FAIL issue304/valid: got $got want 42"; fail=1; fi
  rm -f "$out"
}

## Issue #213 / Types §6.4 / Functions §2.3 / ABI §3.2 / Architecture §7 — the generic call-argument
## `gislice` path may widen local slice passing, but the RV64 write lowering is intentionally narrow:
## only effective `Slice(u64)` and `Slice(u32)` word elements are supported, and checked indices must stay
## in the runtime view length. These generated sources stay in this row's private scratch directory, so
## they add no corpus rows and cannot authorize an oracle change. The existing u64 and aggregate controls
## remain unchanged; the u32 controls cover the supported write and its checked OOB boundary.
issue213_rv64_slice_controls_test() {
  command -v riscv64-unknown-linux-gnu-as >/dev/null 2>&1 && command -v riscv64-unknown-linux-gnu-ld >/dev/null 2>&1 && command -v qemu-riscv64 >/dev/null 2>&1 \
    || { echo "skip issue213_rv64_slice_controls: riscv64 toolchain absent"; return; }
  local d="$T/issue213_rv64_slice_controls"
  rm -rf "$d"
  mkdir -p "$d" || { echo "FAIL issue213_rv64_slice_controls: scratch"; fail=1; return; }
  printf '%s\n' \
    'setw := fn(T : type, s : Slice(T), i : usize, x : T) { s[i] = x }' \
    'main := fn() -> u64 {' \
    '  arr : [u64; 1] = [10]' \
    '  s := arr[0..1]' \
    '  setw(u64, s, 1, 99)' \
    '  return 42' \
    '}' > "$d/oob.al"
  printf '%s\n' \
    'setw := fn(T : type, s : Slice(T), i : usize, x : T) { s[i] = x }' \
    'main := fn() -> u64 {' \
    '  arr : [u32; 1] = [10]' \
    '  s := arr[0..1]' \
    '  setw(u32, s, 0, 99)' \
    '  return 42' \
    '}' > "$d/u32.al"
  printf '%s\n' \
    'setw := fn(T : type, s : Slice(T), i : usize, x : T) { s[i] = x }' \
    'main := fn() -> u64 {' \
    '  arr : [u32; 3] = [10, 20, 30]' \
    '  s := arr[0..3]' \
    '  setw(u32, s, 3, 99)' \
    '  return 42' \
    '}' > "$d/u32_oob.al"
  printf '%s\n' \
    'P := struct { x : u64 }' \
    'setw := fn(T : type, s : Slice(T), i : usize, x : T) { s[i] = x }' \
    'main := fn() -> u64 {' \
    '  arr : [P; 1] = [P(x = 10)]' \
    '  s := arr[0..1]' \
    '  setw(P, s, 0, P(x = 99))' \
    '  return 42' \
    '}' > "$d/aggregate.al"

  issue213_rv64_case() { # name, expected qemu status
    local n="$1" want="$2" src="$d/$1.al" gas="$d/$1.s" obj="$d/$1.o" elf="$d/$1.elf" err="$d/$1.err" rc got
    "$CC" riscv64 "$src" >"$gas" 2>"$err"; rc=$?
    if [ "$rc" != 0 ]; then
      echo "FAIL issue213/$n: emit rc=$rc"
      sed 's/^/  | /' "$err"
      fail=1
      return
    fi
    if { [ "$n" = oob ] || [ "$n" = u32_oob ]; } && ! grep -qF 'bltu a0, t1, 1f' "$gas"; then
      echo "FAIL issue213/$n: missing runtime-length branch before ebreak"
      fail=1
      return
    fi
    riscv64-unknown-linux-gnu-as "$gas" -o "$obj" 2>"$err"; rc=$?
    if [ "$rc" != 0 ]; then
      echo "FAIL issue213/$n: assemble rc=$rc"
      sed 's/^/  | /' "$err"
      fail=1
      return
    fi
    riscv64-unknown-linux-gnu-ld "$obj" -o "$elf" 2>"$err"; rc=$?
    if [ "$rc" != 0 ]; then
      echo "FAIL issue213/$n: link rc=$rc"
      sed 's/^/  | /' "$err"
      fail=1
      return
    fi
    _e2e_exec qemu-riscv64 "$elf" >/dev/null 2>&1; got=$?
    if _e2e_runtime_failure "issue213/$n(rv64)" "$got"; then return; fi
    if [ "$got" = "$want" ]; then echo "ok   issue213/$n(rv64): $got"; else echo "FAIL issue213/$n(rv64): got $got want $want"; fail=1; fi
  }

  issue213_rv64_case oob 133
  issue213_rv64_case u32 42
  issue213_rv64_case u32_oob 133
  issue213_rv64_case aggregate 133
}

# `alatyr fmt`: re-emit a source file in canonical form. Checks (1) IDEMPOTENCE
# (fmt(fmt(x)) == fmt(x), the acceptance property), and (2) the formatted output still BUILDS+RUNS to
# the expected exit — a faithful reformat must preserve behaviour.
fmt_test() { # name, want-exit
  src="$E2E_TEST/$1.al"
  [ -f "$src" ] || { echo "MISS $1: no $src"; fail=1; return; }
  o1="$T/e2e_$1.fmt1.al"; o2="$T/e2e_$1.fmt2.al"
  "$CC" fmt "$src" > "$o1" 2>/dev/null || { echo "FAIL $1(fmt): emit"; fail=1; return; }
  [ -s "$o1" ] || { echo "FAIL $1(fmt): empty output"; fail=1; return; }
  "$CC" fmt "$o1" > "$o2" 2>/dev/null || { echo "FAIL $1(fmt): re-emit"; fail=1; return; }
  diff -q "$o1" "$o2" >/dev/null || { echo "FAIL $1(fmt): NOT idempotent"; fail=1; return; }
  # comment fidelity: the formatted output must retain as many `##` comment lines as the source
  # (idempotence alone would also be satisfied by dropping them, so assert preservation directly).
  sc=$(grep -c '##' "$src"); oc=$(grep -c '##' "$o1")
  [ "$sc" = "$oc" ] || { echo "FAIL $1(fmt): comments $oc want $sc"; fail=1; return; }
  # The embed fixtures resolve their controlled path relative to the compiler's current directory.
  # The formatted source is run from its row-private scratch directory, so stage only the checked-in
  # binary it names; never make the helper depend on another row's or the repository's target tree.
  if grep -qF 'embed(' "$src"; then
    mkdir -p "$T/test"
    cp "$E2E_TEST/embed_fixture.bin" "$T/test/embed_fixture.bin" || { echo "FAIL $1(fmt): embed fixture staging"; fail=1; return; }
  fi
  # Run the formatted output. The basename must be a CLEAN identifier (no leading '.'/'-'): the module
  # name is derived from it and becomes a GAS symbol, so a dotfile name emits an invalid `.alatyr`
  # pseudo-op. It must also be PER ROW. This used to be the fixed `/tmp/fmtrun.al`, which is shared by
  # every row, every worktree and every agent on the machine; with rows running concurrently, one
  # fixture's formatted program was executed under another's expected exit code (measured:
  # `fmt_enum_forms` ran a neighbour's 42 against its own 49). The run happens INSIDE `$T` too, so
  # anything the compiler leaves in the cwd is the row's own.
  run_al="$T/$1_fmtrun.al"
  cp "$o1" "$run_al"
  _e2e_exec_in "$T" "$CC" run "$run_al" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "$1(fmt)" "$got"; then return; fi
  if [ "$got" = "$2" ]; then echo "ok   $1(fmt): idempotent + runs $got"; else echo "FAIL $1(fmt): formatted runs $got want $2"; fail=1; fi
}

# fmt_test PLUS assert the formatted output CONTAINS a needle (idempotence + run cannot catch a dropped
# marker like `pub`, which has no single-file runtime effect — so check emission directly).
fmt_test_has() { # name, want-exit, needle
  fmt_test "$1" "$2"
  o1="$T/e2e_$1.fmt1.al"
  [ -f "$o1" ] || return
  if grep -qF "$3" "$o1"; then echo "ok   $1(fmt-has): [$3]"; else echo "FAIL $1(fmt-has): missing [$3]"; fail=1; fi
}

# `fmt_test` plus several exact spelling needles. One formatter run is enough to lock all lexical
# variants; repeating `fmt_test_has` would multiply the expensive source/build/idempotence check.
fmt_test_has_all() { # name, want-exit, needle ...
  name="$1"
  fmt_test "$name" "$2"
  o1="$T/e2e_$name.fmt1.al"
  [ -f "$o1" ] || return
  shift 2
  for needle in "$@"; do
    if grep -qF "$needle" "$o1"; then echo "ok   $name(fmt-has): [$needle]"; else echo "FAIL $name(fmt-has): missing [$needle]"; fail=1; fi
  done
}

# A construct fmt CANNOT represent faithfully must be REFUSED, not guessed at. Embed is intentionally
# absent from the refusal table: its path span is now retained and the focused rows below assert the
# emitted path, idempotence, and byte-exact execution.
fmt_refuses() { # name -- fmt must exit non-zero
  src="$E2E_TEST/$1.al"
  [ -f "$src" ] || { echo "MISS fmt_refuses_$1: no $src"; fail=1; return; }
  ( ulimit -c 0; "$CC" fmt "$src" >/dev/null 2>&1 ); got=$?
  if [ "$got" != 0 ]; then echo "ok   fmt_refuses_$1: refused with rc $got"; else echo "FAIL fmt_refuses_$1: rendered (rc 0) a construct it cannot represent"; fail=1; fi
}

# Formatter-only companion for a source fixture whose original program is deliberately check-only
# because its unrelated overload set does not link. It proves the embed path survives two formatter
# passes and remains semantically accepted without turning that pre-existing linker boundary into a
# false formatter failure.
fmt_check() { # name
  src="$E2E_TEST/$1.al"
  [ -f "$src" ] || { echo "MISS $1(fmt-check): no $src"; fail=1; return; }
  o1="$T/e2e_$1.fmt1.al"; o2="$T/e2e_$1.fmt2.al"
  "$CC" fmt "$src" > "$o1" 2>/dev/null || { echo "FAIL $1(fmt-check): emit"; fail=1; return; }
  [ -s "$o1" ] || { echo "FAIL $1(fmt-check): empty output"; fail=1; return; }
  "$CC" fmt "$o1" > "$o2" 2>/dev/null || { echo "FAIL $1(fmt-check): re-emit"; fail=1; return; }
  diff -q "$o1" "$o2" >/dev/null || { echo "FAIL $1(fmt-check): NOT idempotent"; fail=1; return; }
  sc=$(grep -c '##' "$src"); oc=$(grep -c '##' "$o1")
  [ "$sc" = "$oc" ] || { echo "FAIL $1(fmt-check): comments $oc want $sc"; fail=1; return; }
  if grep -qF 'embed(' "$src"; then
    mkdir -p "$T/test"
    cp "$E2E_TEST/embed_fixture.bin" "$T/test/embed_fixture.bin" || { echo "FAIL $1(fmt-check): embed fixture staging"; fail=1; return; }
  fi
  ( cd "$T" && "$CC" check "$o1" >/dev/null 2>&1 ) || { echo "FAIL $1(fmt-check): formatted source no longer checks"; fail=1; return; }
  echo "ok   $1(fmt-check): accepted + idempotent"
}

# The same assertion, but it also pins WHY fmt refused and that nothing reached stdout. `fmt_refuses` above
# accepts any non-zero exit, so a path that starts refusing for an unrelated reason — or SEGFAULTS, which is
# how the `embed` case first showed up — still passes it. That is the same weakness `build_reject` had before
# `build_reject_has`: a reject helper that cannot tell a correct refusal from an accidental one. The stdout
# check matters as much as the needle here, because fmt's ordinary output IS the user's rewritten source: a
# refusal that already printed half a file is not a refusal.
fmt_refuses_has() { # name, needle
  src="$E2E_TEST/$1.al"
  [ -f "$src" ] || { echo "MISS fmt_refuses_has_$1: no $src"; fail=1; return; }
  out="$ROOT/target/e2e_$1.fmtref"; err="$ROOT/target/e2e_$1.fmtreferr"
  ( ulimit -c 0; "$CC" fmt "$src" > "$out" 2>"$err" ); got=$?
  if [ "$got" = 0 ]; then echo "FAIL fmt_refuses_has_$1: rendered (rc 0) a construct it cannot represent"; fail=1; return; fi
  if [ -s "$out" ]; then echo "FAIL fmt_refuses_has_$1: rc=$got but $(wc -c < "$out") bytes of source reached stdout"; fail=1; return; fi
  if ! grep -qF "$2" "$err"; then echo "FAIL fmt_refuses_has_$1: rc=$got, nothing written, but the diagnostic is missing [$2]"; fail=1; return; fi
  echo "ok   fmt_refuses_has_$1: refused with rc $got, wrote nothing, named the reason"
}

# `alatyr fmt` across MODULES: a struct literal whose struct DECL lives in an IMPORTED
# module is absent from this file's decls, so field-name recovery must SOURCE-SCAN the literal rather
# than look up the decl (else fail-loud "struct literal of unknown struct" — the dominant multi-module
# gap). Single-file fmt can't resolve the import, so this builds a 2-module package and fmt's the
# CONSUMER: it must not fail-loud, must be idempotent, and the bare / generic-instance / qualified head
# names + `name = value` fields must survive verbatim (there is no local decl to recover them from).
fmt_crossmod_test() {
  pd="$T/e2e_fmtxmod"
  rm -rf "$pd"; mkdir -p "$pd/src"
  printf 'pub Point := struct { x : u64, y : u64 }\npub Box := fn(T : type) -> type { struct { v : u64 } }\n' > "$pd/src/geo.al"
  printf 'geo := "geo.al"\n(Point, Box) := geo\nuse := fn() -> u64 {\n  p := Point(x = 1, y = 2)\n  b := Box(u64)(v = 3)\n  q := geo::Point(x = 4, y = 5)\n  p.x + b.v + q.y\n}\n' > "$pd/src/consumer.al"
  o1="$pd/c1.al"; o2="$pd/c2.al"
  "$CC" fmt "$pd/src/consumer.al" > "$o1" 2>/dev/null || { echo "FAIL fmt_crossmod: emit (fail-loud on imported struct)"; fail=1; return; }
  [ -s "$o1" ] || { echo "FAIL fmt_crossmod: empty output"; fail=1; return; }
  "$CC" fmt "$o1" > "$o2" 2>/dev/null || { echo "FAIL fmt_crossmod: re-emit"; fail=1; return; }
  diff -q "$o1" "$o2" >/dev/null || { echo "FAIL fmt_crossmod: NOT idempotent"; fail=1; return; }
  grep -qF 'Point(x = 1, y = 2)' "$o1"     || { echo "FAIL fmt_crossmod: bare struct-lit fields lost"; fail=1; return; }
  grep -qF 'Box(u64)(v = 3)' "$o1"         || { echo "FAIL fmt_crossmod: generic-instance head/fields lost"; fail=1; return; }
  grep -qF 'geo::Point(x = 4, y = 5)' "$o1" || { echo "FAIL fmt_crossmod: qualified head lost"; fail=1; return; }
  echo "ok   fmt_crossmod: bare + generic + qualified imported struct-lits round-trip"
}

# Tooling §4.3 — no-path `fmt` rewrites every `.al` below the package root in place. This locks the
# package-wide contract: deterministic recursive discovery, manifest inclusion, idempotence, and the
# required invalid-file behavior (the malformed file remains byte-for-byte unchanged and is reported).
# TOOL-10 / I11 on the OUTPUT descriptor: a path that writes its result to stdout must report a failed or
# SHORT write, not exit 0 having produced nothing or half of something. Measured before the fix, on all three
# of `alatyr <file>` (the x86 GAS dump), `alatyr fmt <file>` and the very command `scripts/fixpoint.sh`
# captures — every one exited **0** with the redirection broken. That last one is why this is a gate line and
# not a footnote: fixpoint diffs the captured dumps, so a truncated dump exiting 0 makes the gate compare a
# short file against a whole one and report whatever that comparison happens to say — a gate reading a lie.
# No existing helper can express it: they all point stdout at a file or /dev/null, a descriptor that cannot
# fail. Two failure KINDS, because they are different syscall outcomes: an error (`/dev/full` gives ENOSPC,
# a closed descriptor gives EBADF) and a SHORT write (one 64 KiB pipe buffer accepted out of a larger dump).
flush_reject() { # label, argv… (source last)
  label="$1"; shift
  ( ulimit -c 0; "$CC" "$@" > /dev/full 2>"$T/flush_$label.devfull.err" ); got=$?
  if [ "$got" != 0 ]; then echo "ok   flush_$label(/dev/full): reported the failed write with rc $got"
  else echo "FAIL flush_$label(/dev/full): exit 0 on a write that could not succeed"; fail=1; fi
  ( ulimit -c 0; "$CC" "$@" >&- 2>"$T/flush_$label.closed.err" ); got=$?
  if [ "$got" != 0 ]; then echo "ok   flush_$label(closed stdout): reported the failed write with rc $got"
  else echo "FAIL flush_$label(closed stdout): exit 0 with no descriptor to write to"; fail=1; fi
}
# `${PIPESTATUS[0]}`, never `$?` — `$?` is `head`'s and it is 0 every time. And `trap '' PIPE` for the child:
# with the default disposition Linux delivers SIGPIPE before `write` returns, the shell reports 141, and the
# program's OWN status is never observed — so 141 is a failure here, not a pass for the wrong reason.
flush_reject_short() { # label, argv… (source last)
  label="$1"; shift
  ( trap '' PIPE; ulimit -c 0; exec "$CC" "$@" ) 2>"$T/flush_$label.short.err" | head -c 1 >/dev/null
  got=${PIPESTATUS[0]}
  if [ "$got" = 141 ]; then echo "FAIL flush_$label(short pipe): SIGPIPE killed it, the program's own status was never observed"; fail=1
  elif [ "$got" != 0 ]; then echo "ok   flush_$label(short pipe): reported the short write with rc $got"
  else echo "FAIL flush_$label(short pipe): exit 0 having written one buffer of many"; fail=1; fi
}
# The short-write rows need an output LARGER than one 64 KiB pipe buffer on BOTH surfaces, and no tracked
# fixture comes close (the largest fmt output is 5 509 bytes), so the input is generated here rather than
# added to `test/` — which also keeps the corpus manifest untouched. The shape is deliberate: 6 000 calls to
# ONE callee. 33 DISTINCT callees in a single function SEGFAULTS the x86 lower (measured: 32 is fine, 33 is
# rc 139, while `check`, `wat` and `aarch64` all accept it — a separate defect recorded in), and
# generating the obvious 1 000-distinct-function program would have made this row fail for that reason
# instead. Measured on this shape: fmt writes 84 116 bytes in 52 ms, the GAS dump 834 647 bytes in 1.3 s.
# The fmt path carried a FIXED 64 MiB arena while its consumers scale LINEARLY with the source — decls 8 B
# per input byte, ev 16, comments 8, and a `Decl` record bumped per declaration TWICE because pass 1's
# records are never reclaimed. So `alatyr fmt src/lower.al` (1.4 MB, 32 % of the compiler) died with
# `rt: arena overflow (bump past cap)` and zero bytes out: fmt could not format the module that most needs
# it. Measured pre-fix ceiling ~963 KB, and it is DECLARATION-bound, not byte-bound — same 1.2 MB input takes
# 4.71 s as 24 000 one-line decls and 1.14 s as 1 469 long-bodied ones. No tracked fixture can lock this: a
# 1 MB `test/*.al` belongs in neither git nor the corpus manifest, so the input is generated, with one `##`
# per declaration so the comment guard actually bites, and a non-vacuity assertion on the generated size.
fmt_large_input_test() { # min-bytes, want-exit
  fd="$T/e2e_fmtlarge"; rm -rf "$fd"; mkdir -p "$fd"
  src="$fd/fmt_large.al"
  awk -v want="$1" 'BEGIN {
    printf "## A GENERATED input, bigger than the fixed arena the fmt path used to carry.\n"
    printf "f0 := fn() -> u64 { return 0 }\n"
    ## the running byte count is an estimate from `length()`, so overshoot deliberately: the assertion
    ## below is the one that must be satisfied, and it caught a generator that landed 166 B short.
    b = 0; n = 0
    while (b < want + 8192) {
      n += 1
      l = sprintf("## doc comment for the generated function f%d\n", n); printf "%s", l; b += length(l)
      l = sprintf("f%d := fn(x : u64) -> u64 {\n  mut acc : u64 = x\n", n); printf "%s", l; b += length(l)
      for (k = 0; k < 30; k++) { l = sprintf("  acc += %d\n  acc -= %d\n", k, k); printf "%s", l; b += length(l) }
      l = sprintf("  return acc + %d\n}\n", n); printf "%s", l; b += length(l)
    }
    printf "## the entry point: the formatted program must still build and run.\n"
    printf "main := fn() -> u64 { return f1(41) }\n"
  }' > "$src"
  n=$(wc -c < "$src")
  if [ "$n" -lt "$1" ]; then echo "FAIL fmt_large_input: generated $n B, wanted >= $1 B - the row cannot reach the old ceiling"; fail=1; return; fi
  o1="$fd/fmt_large_out.al"; o2="$fd/fmt_large_out2.al"
  ( ulimit -c 0; "$CC" fmt "$src" > "$o1" 2>"$fd/err" ) || { echo "FAIL fmt_large_input: fmt of $n B failed [$(head -c 120 "$fd/err")]"; fail=1; return; }
  [ -s "$o1" ] || { echo "FAIL fmt_large_input: empty output"; fail=1; return; }
  ( ulimit -c 0; "$CC" fmt "$o1" > "$o2" 2>/dev/null ) || { echo "FAIL fmt_large_input: re-emit"; fail=1; return; }
  diff -q "$o1" "$o2" >/dev/null || { echo "FAIL fmt_large_input: NOT idempotent"; fail=1; return; }
  sc=$(grep -c '##' "$src"); oc=$(grep -c '##' "$o1")
  [ "$sc" = "$oc" ] || { echo "FAIL fmt_large_input: comments $oc want $sc"; fail=1; return; }
  _e2e_exec_in "$fd" "$CC" run "$o1" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "fmt_large_input" "$got"; then return; fi
  if [ "$got" = "$2" ]; then echo "ok   fmt_large_input: $n B formatted, idempotent, $sc comments kept, runs $got"
  else echo "FAIL fmt_large_input: formatted runs $got want $2"; fail=1; fi
}

flush_status_test() {
  fd="$T/e2e_flush"; rm -rf "$fd"; mkdir -p "$fd"
  printf 'main := fn() -> u64 {\n  return 42\n}\n' > "$fd/small.al"
  printf 'f0 := fn() -> u64 { return 1 }\nmain := fn() -> u64 {\n  mut acc : u64 = 0\n' > "$fd/big.al"
  i=0; while [ "$i" -lt 6000 ]; do printf '  acc += f0()\n' >> "$fd/big.al"; i=$((i+1)); done
  printf '  if acc == 0 { return 1 }\n  42\n}\n' >> "$fd/big.al"
  ( ulimit -c 0; "$CC" "$fd/big.al" > "$fd/big.s" 2>/dev/null ) || { echo "FAIL flush_status: the generated source does not compile"; fail=1; return; }
  ( ulimit -c 0; "$CC" fmt "$fd/big.al" > "$fd/big.fmt" 2>/dev/null ) || { echo "FAIL flush_status: the generated source does not format"; fail=1; return; }
  nd=$(wc -c < "$fd/big.s"); nf=$(wc -c < "$fd/big.fmt")
  if [ "$nd" -le 65536 ] || [ "$nf" -le 65536 ]; then
    echo "FAIL flush_status: generated dump $nd B / fmt $nf B — one pipe buffer or less on a surface, so its short-write row would prove nothing"; fail=1; return
  fi
  echo "ok   flush_status: generated dump $nd B and fmt $nf B, both past one 64 KiB pipe buffer"
  flush_reject dump "$fd/small.al"
  flush_reject fmt fmt "$fd/small.al"
  flush_reject_short dump "$fd/big.al"
  flush_reject_short fmt fmt "$fd/big.al"
}

# Issue #226 / runtime robustness: the compiler's internal `rt::Arena` constructor must turn a
# failed `mmap` into its defined panic (stderr + exit 1) before publishing a pointer. The source is
# generated in the row-private directory so this harness does not add an oracle row. Parent evidence
# on origin/main before the fix: with `ulimit -v 32768`, this valid input made `check` die with rc=139
# (SIGSEGV) and no diagnostic; without the limit it returned 0.
arena_init_mmap_failure_test() {
  fd="$T/e2e_arena_init_failure"; rm -rf "$fd"; mkdir -p "$fd"
  src="$fd/arena_init_mmap_failure.al"
  printf '%s\n' \
    '## Valid input used to exercise the compiler startup arena under a deterministic address-space limit.' \
    '## On the parent compiler, `ulimit -v 32768` produced rc=139 (SIGSEGV) before this fix.' \
    'main := fn() -> u64 { return 42 }' > "$src"
  "$CC" check "$src" >/dev/null 2>&1 || { echo "FAIL arena_init_mmap_failure: unrestricted startup"; fail=1; return; }
  out="$fd/stdout"; err="$fd/stderr"
  ( ulimit -c 0; ulimit -v 32768 || exit 125; "$CC" check "$src" >"$out" 2>"$err" ); got=$?
  if [ "$got" != 1 ]; then
    echo "FAIL arena_init_mmap_failure: constrained check rc=$got want 1 (mmap failure must panic)"
    fail=1; return
  fi
  if [ -s "$out" ]; then
    echo "FAIL arena_init_mmap_failure: constrained check wrote $(wc -c < "$out") bytes to stdout"
    fail=1; return
  fi
  if grep -qF 'rt: arena initialization failed (mmap)' "$err"; then
    echo "ok   arena_init_mmap_failure: startup survives mmap failure with controlled rc=1"
  else
    echo "FAIL arena_init_mmap_failure: diagnostic missing [rt: arena initialization failed (mmap)]"
    fail=1
  fi
}

fmt_package_test() {
  pd="$T/e2e_fmtpkg"
  rm -rf "$pd"; mkdir -p "$pd/src/nested"
  printf 'app:=Package(version="0.1.0",source_dir="src",target_dir="target",targets=[Target(arch=Arch.x86_64,os=Os.linux,env=Env.gnu,container=Container.elf,entry="_start",output="fmtpkg")])\n' > "$pd/package.al"
  printf 'main:=fn()->u64{\nreturn 42\n}\n' > "$pd/src/a.al"
  printf 'value:=fn()->u64{return 1}\n' > "$pd/src/b.al"
  printf 'nested:=fn()->u64{return 3}\n' > "$pd/src/nested/c.al"
  ( cd "$pd" && "$CC" fmt ) >/dev/null 2>&1 || { echo "FAIL fmt_package: valid package rewrite"; fail=1; return; }
  grep -qF 'app := Package(' "$pd/package.al" || { echo "FAIL fmt_package: manifest not formatted"; fail=1; return; }
  grep -qF 'main := fn() -> u64 {' "$pd/src/a.al" || { echo "FAIL fmt_package: source not formatted"; fail=1; return; }
  grep -qF 'nested := fn() -> u64 {' "$pd/src/nested/c.al" || { echo "FAIL fmt_package: nested source not formatted"; fail=1; return; }
  before="$pd/before.sha256"; after="$pd/after.sha256"
  find "$pd" -type f -name '*.al' -print0 | sort -z | xargs -0 sha256sum > "$before"
  ( cd "$pd" && "$CC" fmt ) >/dev/null 2>&1 || { echo "FAIL fmt_package: second rewrite"; fail=1; return; }
  find "$pd" -type f -name '*.al' -print0 | sort -z | xargs -0 sha256sum > "$after"
  diff -q "$before" "$after" >/dev/null || { echo "FAIL fmt_package: NOT idempotent"; fail=1; return; }
  printf 'not valid syntax !!!\n' > "$pd/src/z.al"
  cp "$pd/src/z.al" "$pd/invalid.before"
  ( cd "$pd" && "$CC" fmt ) >/dev/null 2>&1; got=$?
  if [ "$got" = 0 ]; then echo "FAIL fmt_package: invalid source accepted"; fail=1; return; fi
  cmp -s "$pd/src/z.al" "$pd/invalid.before" || { echo "FAIL fmt_package: invalid source changed"; fail=1; return; }
  echo "ok   fmt_package: recursive + manifest + idempotent + invalid unchanged"
}

# manifest `Target.entry`: build a package whose manifest names a NON-default ELF entry
# symbol, run the artifact (exit must match), and confirm the entry is a REAL exported symbol rather
# than a compiler-synthesized `<entry> -> main__main` wrapper. Keeping `main` with a different exit
# value proves the loader starts at `@export("myentry")`, while an old wrapper would duplicate `myentry`.
# The exported entry exits directly: ELF jumps to it without a caller, so a normal `return` would be invalid.
manifest_entry_test() { # want-exit
  pd="$T/e2e_pkgentry"
  rm -rf "$pd"; mkdir -p "$pd/src"
  printf 'app := Package(version = "0.1.0", source_dir = "src", target_dir = "target", targets = [\n  Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf, entry = "myentry", output = "prog"),\n])\n' > "$pd/package.al"
  printf '@export("myentry") entry := fn() { exit(%s) }\nmain := fn() -> u64 { return 7 }\n' "$1" > "$pd/src/main.al"
  ( cd "$pd" && "$CC" build package.al ) >/dev/null 2>&1 || { echo "FAIL manifest_entry: build"; fail=1; return; }
  _e2e_exec "$pd/target/debug/prog" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "manifest_entry" "$got"; then return; fi
  if [ "$got" != "$1" ]; then echo "FAIL manifest_entry: exit=$got want=$1"; fail=1; return; fi
  if nm "$pd/target/debug/prog" 2>/dev/null | grep -q ' T myentry'; then echo "ok   manifest_entry: exit $got, entry symbol myentry"; else echo "FAIL manifest_entry: no 'myentry' entry symbol"; fail=1; fi
}

# TOOL-6/P3 — split builds publish a deterministic exported interface/layout summary next to the
# artifact. This is deliberately a two-module package so the split path is exercised; a cold rebuild
# must reproduce the sidecar byte-for-byte and expose both scalar signatures and resolved layout facts.
interface_summary_test() {
  pd="$T/e2e_iface_summary"; rm -rf "$pd"; mkdir -p "$pd/src"
  cat > "$pd/package.al" <<'EOF'
app := Package(version = "0.1.0", source_dir = "src", target_dir = "target", targets = [
  Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf, entry = "_start", output = "iface"),
])
EOF
  cat > "$pd/src/types.al" <<'EOF'
pub Point := struct { x : u64, y : u64 }
pub make_point := fn() -> Point { Point(x = 40, y = 2) }
EOF
cat > "$pd/src/main.al" <<'EOF'
answer := @export("answer_export") fn() -> u64 { return 42 }
main := fn() -> u64 { return answer() }
EOF
  ( cd "$pd" && ALATYR_OSPLIT=1 "$CC" build package.al ) >/dev/null 2>&1 || { echo "FAIL interface_summary: split build"; fail=1; return; }
bin="$pd/target/debug/iface"; side="$pd/target/debug/iface.interface"
  [ -x "$bin" ] || { echo "FAIL interface_summary: no artifact"; fail=1; return; }
  [ -s "$side" ] || { echo "FAIL interface_summary: no sidecar"; fail=1; return; }
  _e2e_exec "$bin" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "interface_summary" "$got"; then return; fi
  if [ "$got" != 42 ]; then echo "FAIL interface_summary: artifact exit=$got want=42"; fail=1; return; fi
  grep -qF 'format=alatyr-interface-summary' "$side" || { echo "FAIL interface_summary: format marker"; fail=1; return; }
  grep -qF 'hash=fnv1a64' "$side" || { echo "FAIL interface_summary: hash marker"; fail=1; return; }
  grep -qF 'module_count=2' "$side" || { echo "FAIL interface_summary: module count"; fail=1; return; }
  grep -qF 'decl kind=struct name=Point' "$side" || { echo "FAIL interface_summary: Point signature"; fail=1; return; }
  grep -qF 'field name=x' "$side" || { echo "FAIL interface_summary: Point field layout"; fail=1; return; }
  grep -qF 'decl kind=fn name=make_point' "$side" || { echo "FAIL interface_summary: function signature"; fail=1; return; }
  grep -qF 'decl kind=fn name=answer' "$side" || { echo "FAIL interface_summary: exported function"; fail=1; return; }
  grep -qF 'module_interface_hash=' "$side" || { echo "FAIL interface_summary: per-module hash"; fail=1; return; }
  grep -qF 'module=main' "$side" || { echo "FAIL interface_summary: second module"; fail=1; return; }
  grep -qF 'interface_hash=' "$side" || { echo "FAIL interface_summary: aggregate hash"; fail=1; return; }
  first_hash="$(awk -F= '$1 == "interface_hash" { print $2; exit }' "$side")"
  [ -n "$first_hash" ] || { echo "FAIL interface_summary: empty aggregate hash"; fail=1; return; }
  cp "$side" "$pd/first.interface"
rm -f "$pd/target/debug/iface" "$pd/target/debug/iface.interface" "$pd/target/debug/iface.manifest"
  ( cd "$pd" && ALATYR_OSPLIT=1 "$CC" build package.al ) >/dev/null 2>&1 || { echo "FAIL interface_summary: cold rebuild"; fail=1; return; }
  cmp -s "$pd/first.interface" "$side" || { echo "FAIL interface_summary: cold sidecar is not deterministic"; fail=1; return; }
  # Adversarial invalidation: change an observable exported layout fact while keeping the package
  # buildable and its runtime result unchanged. A cache key that omits layout would incorrectly
  # reuse the previous sidecar/hash here.
  sed -i 's/y : u64/y2 : u64/; s/y = 2/y2 = 2/' "$pd/src/types.al"
  grep -qF 'y2 : u64' "$pd/src/types.al" || { echo "FAIL interface_summary: API mutation"; fail=1; return; }
rm -f "$pd/target/debug/iface" "$pd/target/debug/iface.interface" "$pd/target/debug/iface.manifest"
  ( cd "$pd" && ALATYR_OSPLIT=1 "$CC" build package.al ) >/dev/null 2>&1 || { echo "FAIL interface_summary: changed-API build"; fail=1; return; }
  changed_hash="$(awk -F= '$1 == "interface_hash" { print $2; exit }' "$side")"
  [ -s "$side" ] || { echo "FAIL interface_summary: changed-API sidecar missing"; fail=1; return; }
  if cmp -s "$pd/first.interface" "$side"; then
    echo "FAIL interface_summary: exported layout change did not change sidecar"; fail=1; return
  fi
  if [ "$changed_hash" = "$first_hash" ]; then
    echo "FAIL interface_summary: exported layout change did not change interface hash"; fail=1; return
  fi
  cp "$side" "$pd/changed.interface"
rm -f "$pd/target/debug/iface" "$pd/target/debug/iface.interface" "$pd/target/debug/iface.manifest"
  ( cd "$pd" && ALATYR_OSPLIT=1 "$CC" build package.al ) >/dev/null 2>&1 || { echo "FAIL interface_summary: changed-API cold rebuild"; fail=1; return; }
  cmp -s "$pd/changed.interface" "$side" || { echo "FAIL interface_summary: changed-API cold sidecar is not deterministic"; fail=1; return; }
  _e2e_exec "$bin" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "interface_summary" "$got"; then return; fi
  if [ "$got" != 42 ]; then echo "FAIL interface_summary: changed-API artifact exit=$got want=42"; fail=1; return; fi
  echo "ok   interface_summary: API/layout facts + cold determinism + adversarial invalidation"
}

# a flat single-file package may define its own default `_start` directly in
# `package.al` when no source modules are present. The manifest binding is inert source data; the
# user-defined `_start` must remain the ELF entry and must not be replaced by a `main__main` wrapper.
single_file_start_test() {
  pd="$T/e2e_single_start"
  rm -rf "$pd"; mkdir -p "$pd"
  cat > "$pd/package.al" <<'EOF'
app := Package(version = "0.1.0")
print := std::fmt::print

_start := fn() {
  print("Hello, world!\n")
  exit(0)
}
EOF
  ( cd "$pd" && "$CC" check package.al ) >/dev/null 2>&1 || { echo "FAIL single_file_start: check"; fail=1; return; }
  ( cd "$pd" && "$CC" build package.al ) >/dev/null 2>&1 || { echo "FAIL single_file_start: build"; fail=1; return; }
  stdout="$T/e2e_single_start.stdout"
  _e2e_exec_capture "$stdout" "$pd/target/debug/a.out" 2>/dev/null; rc=$?
  out="$(<"$stdout")"
  if _e2e_runtime_failure "single_file_start(artifact)" "$rc"; then return; fi
  if [ "$rc" != 0 ] || [ "$out" != "Hello, world!" ]; then
    echo "FAIL single_file_start: artifact output=[$out] rc=$rc"; fail=1; return
  fi
  stdout="$T/e2e_single_start.run.stdout"
  _e2e_exec_capture_in "$stdout" "$pd" "$CC" run package.al 2>/dev/null; rc=$?
  out="$(<"$stdout")"
  if _e2e_runtime_failure "single_file_start(run)" "$rc"; then return; fi
  if [ "$rc" = 0 ] && [ "$out" = "Hello, world!" ]; then
    echo "ok   single_file_start: check + build/run + default _start"
  else
    echo "FAIL single_file_start: run output=[$out] rc=$rc"; fail=1
  fi
}

# FND-11 (Tooling §2.3) — manifest `limits` CEILING vs a file's `@limits`: a file may only be STRICTER
# (its @limits must be ⊇ the ceiling). Three package builds against ceiling `[no_alloc]`:
#  - REJECT: a module whose @limits OMITS a ceiling limit (`@limits(no_comptime)`) → build fails loud;
#  - ACCEPT: a module whose @limits is ⊇ the ceiling (`@limits(no_alloc, no_comptime)`) → builds + runs;
#  - INHERIT: a module with NO @limits inherits the ceiling → builds. Proves the ceiling is read from
#    the manifest and the stricter-than-ceiling contract is enforced only at the manifest-build path.
manifest_limits_ceiling_test() {
  hdr='app := Package(version = "0.1.0", source_dir = "src", target_dir = "target", limits = [no_alloc], targets = [\n  Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf, entry = "_start", output = "prog"),\n])\n'
  # REJECT
  pd="$T/e2e_limceil_rej"; rm -rf "$pd"; mkdir -p "$pd/src"
  printf "$hdr" > "$pd/package.al"
  printf '@limits(no_comptime)\nmain := fn() -> u64 { return 0 }\n' > "$pd/src/main.al"
  msg="$( cd "$pd" && "$CC" build package.al 2>&1 >/dev/null )"; rc=$?
  if [ "$rc" != 0 ]; then echo "ok   manifest_limits_ceiling(reject): laxer @limits build rejected"; else echo "FAIL manifest_limits_ceiling(reject): build succeeded, want fail-loud"; fail=1; fi
  # FND-10/11 build-time located diagnostic (§1 item 6 / §5): the fail-loud abort must carry a
  # SOURCE LOCATION (the `@limits` marker is on line 1 of main.al), not a bare unlocated panic.
  case "$msg" in
    *"at line 1 in main"*) echo "ok   manifest_limits_ceiling(reject): located line 1 in main" ;;
    *) echo "FAIL manifest_limits_ceiling(reject): want 'at line 1 in main', got: $msg"; fail=1 ;;
  esac
  # ACCEPT
  pa="$T/e2e_limceil_acc"; rm -rf "$pa"; mkdir -p "$pa/src"
  printf "$hdr" > "$pa/package.al"
  printf '@limits(no_alloc, no_comptime)\nmain := fn() -> u64 { return 7 }\n' > "$pa/src/main.al"
  ( cd "$pa" && "$CC" build package.al ) >/dev/null 2>&1 || { echo "FAIL manifest_limits_ceiling(accept): build"; fail=1; return; }
  _e2e_exec "$pa/target/debug/prog" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "manifest_limits_ceiling(accept)" "$got"; then return; fi
  if [ "$got" = 7 ]; then echo "ok   manifest_limits_ceiling(accept): stricter @limits builds + runs 7"; else echo "FAIL manifest_limits_ceiling(accept): exit=$got want=7"; fail=1; fi
  # INHERIT (no @limits)
  pi="$T/e2e_limceil_inh"; rm -rf "$pi"; mkdir -p "$pi/src"
  printf "$hdr" > "$pi/package.al"
  printf 'main := fn() -> u64 { return 5 }\n' > "$pi/src/main.al"
  ( cd "$pi" && "$CC" build package.al ) >/dev/null 2>&1
  if [ "$?" = 0 ]; then echo "ok   manifest_limits_ceiling(inherit): no @limits inherits ceiling, builds"; else echo "FAIL manifest_limits_ceiling(inherit): build failed, want accept"; fail=1; fi
  # ENFORCE: a no-@limits module INHERITS the ceiling AND is restricted by it — a ceiling `[no_unchecked]`
  # with a module (no @limits) that USES `unchecked` must fail the build (the ceiling is enforced, not
  # merely validated against a present @limits).
  hdru='app := Package(version = "0.1.0", source_dir = "src", target_dir = "target", limits = [no_unchecked], targets = [\n  Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf, entry = "_start", output = "prog"),\n])\n'
  pe="$T/e2e_limceil_enf"; rm -rf "$pe"; mkdir -p "$pe/src"
  printf "$hdru" > "$pe/package.al"
  printf 'main := fn() -> u64 { return unchecked (40 + 2) }\n' > "$pe/src/main.al"
  msg="$( cd "$pe" && "$CC" build package.al 2>&1 >/dev/null )"; rc=$?
  if [ "$rc" != 0 ]; then echo "ok   manifest_limits_ceiling(enforce): inherited ceiling limit enforced (unchecked rejected)"; else echo "FAIL manifest_limits_ceiling(enforce): build succeeded, want fail-loud"; fail=1; fi
  # the inherited-ceiling violation is located at the offending fn (main, line 1).
  case "$msg" in
    *"at line 1 in main"*) echo "ok   manifest_limits_ceiling(enforce): located line 1 in main" ;;
    *) echo "FAIL manifest_limits_ceiling(enforce): want 'at line 1 in main', got: $msg"; fail=1 ;;
  esac
  pc="$T/e2e_limceil_check"; rm -rf "$pc"; mkdir -p "$pc/src"
  printf "$hdru" > "$pc/package.al"
  printf 'main := fn() -> u64 { return unchecked (40 + 2) }\n' > "$pc/src/main.al"
  ( cd "$pc" && "$CC" check package.al ) >/dev/null 2>&1
  if [ "$?" != 0 ]; then echo "ok   manifest_limits_ceiling(check): inherited ceiling limit enforced in check"; else echo "FAIL manifest_limits_ceiling(check): check accepted, want reject"; fail=1; fi
}

# FND-11 / codec probe — the checked-in package fixtures use the manifest's enum projection spelling
# (`Limit.*`) and exercise every package-aware verb. Keep these separate from the generated ceiling
# helper above: that helper's bare names protect the original scanner contract, while this row locks the
# syntax the real Manifest type exposes. Rejecting through `run`/`test` matters because both compile the
# package before dispatching the result; accepting an equal file contract proves the ceiling is inclusive.
manifest_limits_qualified_package_test() {
  root="$(_fixture_tree package)/limits_ceiling"
  for d in inherited equal capabilities; do
    [ -f "$root/$d/package.al" ] || { echo "MISS manifest_limits_qualified_package: $root/$d/package.al"; fail=1; return; }
  done

  p="$root/inherited"
  for verb in check build run test; do
    err="$T/limits_inherited_$verb.err"
    if [ "$verb" = run ] || [ "$verb" = test ]; then
      _e2e_exec_in "$p" "$CC" "$verb" package.al >/dev/null 2>"$err"; got=$?
      if _e2e_runtime_failure "manifest_limits_qualified_package(inherited/$verb)" "$got"; then return; fi
    else
      ( cd "$p" && "$CC" "$verb" package.al ) >/dev/null 2>"$err"; got=$?
    fi
    if [ "$got" != 0 ] && grep -qF "@limits(no_unchecked) violation" "$err"; then
      echo "ok   manifest_limits_qualified_package(inherited/$verb): rejected with inherited ceiling"
    else
      echo "FAIL manifest_limits_qualified_package(inherited/$verb): rc=$got, want located no_unchecked reject"
      fail=1
    fi
  done

  p="$root/equal"
  ( cd "$p" && "$CC" check package.al ) >/dev/null 2>&1; got=$?
  if [ "$got" = 0 ]; then echo "ok   manifest_limits_qualified_package(equal/check): accepted"; else echo "FAIL manifest_limits_qualified_package(equal/check): rc=$got want 0"; fail=1; fi
  rm -rf "$p/target"
  ( cd "$p" && "$CC" build package.al ) >/dev/null 2>&1; got=$?
if [ "$got" = 0 ] && [ -x "$p/target/debug/limits-equal" ]; then
    _e2e_exec "$p/target/debug/limits-equal" >/dev/null 2>&1; artifact=$?
    if _e2e_runtime_failure "manifest_limits_qualified_package(equal/build)" "$artifact"; then return; fi
    if [ "$artifact" = 42 ]; then echo "ok   manifest_limits_qualified_package(equal/build): artifact 42"; else echo "FAIL manifest_limits_qualified_package(equal/build): artifact=$artifact want 42"; fail=1; fi
  else
    echo "FAIL manifest_limits_qualified_package(equal/build): rc=$got or artifact missing"; fail=1
  fi
  rm -rf "$p/target"
  _e2e_exec_in "$p" "$CC" run package.al >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "manifest_limits_qualified_package(equal/run)" "$got"; then return; fi
  if [ "$got" = 42 ]; then echo "ok   manifest_limits_qualified_package(equal/run): 42"; else echo "FAIL manifest_limits_qualified_package(equal/run): rc=$got want 42"; fail=1; fi
  _e2e_exec_in "$p" "$CC" test package.al >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "manifest_limits_qualified_package(equal/test)" "$got"; then return; fi
  if [ "$got" = 0 ]; then echo "ok   manifest_limits_qualified_package(equal/test): 0"; else echo "FAIL manifest_limits_qualified_package(equal/test): rc=$got want 0"; fail=1; fi
  rm -rf "$p/target"

  p="$root/capabilities"
  for verb in check build run test; do
    err="$T/limits_capabilities_$verb.err"
    if [ "$verb" = run ] || [ "$verb" = test ]; then
      _e2e_exec_in "$p" "$CC" "$verb" package.al >/dev/null 2>"$err"; got=$?
      if _e2e_runtime_failure "manifest_limits_qualified_package(capabilities/$verb)" "$got"; then return; fi
    else
      ( cd "$p" && "$CC" "$verb" package.al ) >/dev/null 2>"$err"; got=$?
    fi
    if [ "$got" != 0 ] && grep -qF "@limits(no_alloc) violation" "$err"; then
      echo "ok   manifest_limits_qualified_package(capabilities/$verb): rejected with no_alloc ceiling"
    else
      echo "FAIL manifest_limits_qualified_package(capabilities/$verb): rc=$got, want located no_alloc reject"
      fail=1
    fi
  done

  ## Keep a single-limit freestanding package here as well: the checked-in capability fixture reaches
  ## no_alloc first, so it cannot prove that the second qualified enum member is normalized independently.
  pf="$T/limits_freestanding"
  mkdir -p "$pf/src"
  cat > "$pf/package.al" <<'EOF'
app := Package(
  version = "0.1.0",
  source_dir = "src",
  target_dir = "target",
  limits = [Limit.freestanding],
  targets = [Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf, kind = Kind.executable, output = "limits-freestanding")],
)
EOF
  cat > "$pf/src/main.al" <<'EOF'
main := fn() -> u64 {
  std::io::print("")
  42
}
EOF
  for verb in check build run test; do
    err="$T/limits_freestanding_$verb.err"
    if [ "$verb" = run ] || [ "$verb" = test ]; then
      _e2e_exec_in "$pf" "$CC" "$verb" package.al >/dev/null 2>"$err"; got=$?
      if _e2e_runtime_failure "manifest_limits_qualified_package(freestanding/$verb)" "$got"; then return; fi
    else
      ( cd "$pf" && "$CC" "$verb" package.al ) >/dev/null 2>"$err"; got=$?
    fi
    if [ "$got" != 0 ] && grep -qF "@limits(freestanding) violation" "$err"; then
      echo "ok   manifest_limits_qualified_package(freestanding/$verb): rejected with freestanding ceiling"
    else
      echo "FAIL manifest_limits_qualified_package(freestanding/$verb): rc=$got, want located freestanding reject"
      fail=1
    fi
  done
  rm -rf "$root"/inherited/target "$root"/equal/target "$root"/capabilities/target
}

# Tooling §2.7 / §120 (§2.6) — manifest `profile_flags` exposed as the comptime constant `build.<name>`.
# Four package builds (declared defaults, default_profile, per-profile overrides + CLI selection):
#  (1) FOLD: a bool flag (default true) + the built-in `build.debug` (debug default profile) each fold a
#      `comptime if build.<flag>` to its DEFAULT branch (dropped branch absent), and an integer flag used
#      as a BARE VALUE yields its default → exit 10 (1 debug + 2 verbose + 7 max_depth) proves all three;
#  (2) DEFAULT PROFILE: `default_profile = "release"` folds the built-in `build.debug` FALSE (else branch)
#      → exit 42 proves the default-profile selection feeds `build.debug`;
#  (3) PROFILE OVERRIDE: `--profile release` selects a declared profile and its FlagSet override.
#      `--release` is the short spelling for the same profile (the second invocation checks it).
#  (4) LOUD REJECT: an undeclared `build.<name>` FAILS the build (never a silent false/zero).
# Manifest §140 + Modules §6.1 — a package is DISCOVERED with no path argument, and every declaration
# in the package-ROOT file (`package.al`) emits an UNPREFIXED linker symbol. Each fixture is driven
# BOTH ways — a bare `alatyr <cmd>` from inside the package directory and an explicit `package.al` —
# and the two must agree; every program exits 42, checked through `run` AND through the built
# artifact. `nm` pins the emitted symbol NAMES, so a silent regression to `package__x` (or to a
# duplicate `_start` alias) cannot pass. x86_64-only (not matched by the sweeps' `^run [a-z]` grep).
root_package_test() { # dir, expected-symbols...
  d="$1"; shift
  p="$(_fixture_tree package)/$d"
  [ -f "$p/package.al" ] || { echo "MISS root_package($d): no $p/package.al"; fail=1; return; }
  for form in noarg package.al; do
    arg=""; [ "$form" = "package.al" ] && arg="package.al"
    ( cd "$p" && "$CC" check $arg ) >/dev/null 2>&1; got=$?
    if [ "$got" = 0 ]; then echo "ok   root_package($d/$form): check 0"; else echo "FAIL root_package($d/$form): check got $got want 0"; fail=1; fi
    _e2e_exec_in "$p" "$CC" run $arg >/dev/null 2>&1; got=$?
    if _e2e_runtime_failure "root_package($d/$form)" "$got"; then return; fi
    if [ "$got" = 42 ]; then echo "ok   root_package($d/$form): run 42"; else echo "FAIL root_package($d/$form): run got $got want 42"; fail=1; fi
    rm -rf "$p/target"
    ( cd "$p" && "$CC" build $arg ) >/dev/null 2>&1
    exe=$(find "$p/target/debug" -maxdepth 1 -type f ! -name '*.s' ! -name '*.o' 2>/dev/null | head -1)
    [ -x "${exe:-/nonexistent}" ] || { echo "FAIL root_package($d/$form): build produced no artifact"; fail=1; rm -rf "$p/target"; continue; }
    _e2e_exec "$exe" >/dev/null 2>&1; got=$?
    if _e2e_runtime_failure "root_package($d/$form)" "$got"; then return; fi
    if [ "$got" = 42 ]; then echo "ok   root_package($d/$form): artifact 42"; else echo "FAIL root_package($d/$form): artifact got $got want 42"; fail=1; fi
    syms=$(nm "$exe")
    for want in "$@"; do
      if printf '%s\n' "$syms" | grep -qE " $want\$"; then
        echo "ok   root_package($d/$form): symbol $want"
      else
        echo "FAIL root_package($d/$form): symbol $want missing"; fail=1
      fi
    done
    if printf '%s\n' "$syms" | grep -q "package__"; then
      echo "FAIL root_package($d/$form): a root declaration is still module-prefixed (package__...)"; fail=1
    else
      echo "ok   root_package($d/$form): no package__ prefix survives"
    fi
    n=$(printf '%s\n' "$syms" | grep -cE " T _start\$")
    if [ "$n" = 1 ]; then echo "ok   root_package($d/$form): exactly one _start definition"; else echo "FAIL root_package($d/$form): $n _start definitions, want 1"; fail=1; fi
    rm -rf "$p/target"
  done
}

## Issue #269 — a package-owned descendant of `std::os` may name the private OsArena through its
## ancestor, but a direct Result(OsArena, IoError) value must not enter that concrete return sink. Keep
## this package fixture separate from the flat corpus because only the nested module can express the
## exact qualified private type without weakening stdlib visibility. Check and build must agree.
issue269_os_arena_return_test() {
  p="$(_fixture_tree package)/issue269_os_arena_return"
  [ -f "$p/package.al" ] || { echo "MISS issue269_os_arena_return: no $p/package.al"; fail=1; return; }
  for verb in check build; do
    rm -rf "$p/target"
    err="$T/issue269-os-arena-return.$verb.err"
    ( cd "$p" && "$CC" "$verb" package.al ) >/dev/null 2>"$err"
    rc=$?
    artifact="$p/target/debug/issue269-os-arena-return"
    if [ "$rc" = 1 ] && [ ! -e "$artifact" ] && grep -qF "type mismatch" "$err"; then
      echo "ok   issue269_os_arena_return/$verb: rejected with located type-mismatch diagnostic"
    else
      echo "FAIL issue269_os_arena_return/$verb: rc=$rc artifact=$(test -e "$artifact" && echo yes || echo no) diagnostic=$(cat "$err" 2>/dev/null)"
      fail=1
    fi
  done
}

## MOD-8 / Modules §5 + Tooling §2.6 — the anonymous package root merges declarations from package.al
## with direct source_dir child-module names. A root binding may not silently win over a same-named child;
## same-scope root declarations remain rejected, while unrelated root/child names keep the ordinary
## package path green. Check and build must agree on the located Semantic diagnostic.
mod8_root_duplicate_test() {
  root="$(_fixture_tree package)/mod8_root_duplicate"
  for spec in "merged_root_collision|duplicate name at line 1 in mylib" "root_decl_duplicate|duplicate name at line 10 in package"; do
    IFS='|' read -r name needle <<< "$spec"
    p="$root/$name"
    ( cd "$p" && "$CC" check package.al ) >/dev/null 2>"$T/mod8-$name.check.err"
    rc=$?
    if [ "$rc" = 1 ] && grep -qF "$needle" "$T/mod8-$name.check.err"; then
      echo "ok   mod8_root_duplicate/$name: check located [$needle]"
    else
      echo "FAIL mod8_root_duplicate/$name: check rc=$rc diagnostic=$(cat "$T/mod8-$name.check.err" 2>/dev/null)"; fail=1
    fi
    ( cd "$p" && "$CC" build package.al ) >/dev/null 2>"$T/mod8-$name.build.err"
    rc=$?
    if [ "$rc" = 1 ] && grep -qF "$needle" "$T/mod8-$name.build.err"; then
      echo "ok   mod8_root_duplicate/$name: build located [$needle]"
    else
      echo "FAIL mod8_root_duplicate/$name: build rc=$rc diagnostic=$(cat "$T/mod8-$name.build.err" 2>/dev/null)"; fail=1
    fi
  done

  p="$root/legal_root_child"
  rm -rf "$p/target"
  ( cd "$p" && "$CC" check package.al ) >/dev/null 2>"$T/mod8-legal.check.err"
  rc=$?
  if [ "$rc" = 0 ]; then
    echo "ok   mod8_root_duplicate/legal_root_child: unrelated root/child names accepted"
  else
    echo "FAIL mod8_root_duplicate/legal_root_child: check rc=$rc diagnostic=$(cat "$T/mod8-legal.check.err" 2>/dev/null)"; fail=1
  fi
  ( cd "$p" && "$CC" build package.al ) >/dev/null 2>"$T/mod8-legal.build.err"
  rc=$?
  exe=$(find "$p/target/debug" -maxdepth 1 -type f ! -name '*.s' ! -name '*.o' 2>/dev/null | head -1)
  if [ "$rc" = 0 ] && [ -x "${exe:-/nonexistent}" ]; then
    _e2e_exec "$exe" >/dev/null 2>&1; got=$?
    if _e2e_runtime_failure "mod8_root_duplicate/legal_root_child" "$got"; then return; fi
    if [ "$got" = 42 ]; then echo "ok   mod8_root_duplicate/legal_root_child: artifact 42"; else echo "FAIL mod8_root_duplicate/legal_root_child: artifact=$got want 42"; fail=1; fi
  else
    echo "FAIL mod8_root_duplicate/legal_root_child: build rc=$rc artifact missing diagnostic=$(cat "$T/mod8-legal.build.err" 2>/dev/null)"; fail=1
  fi
  rm -rf "$root"/*/target
}

## BYTES — a bounded fixed-byte-array return call is not a compile-time global image. The
## tracked dual fixture locks the const path's existing aggregate-global diagnostic; the row-local
## mutable-only source independently locks the indexed-read guard, so either declaration order cannot
## hide the other path behind an earlier failure.
p1_bytes_global_test() {
  src="$E2E_TEST/p1_bytes_global_reject.al"
  err="$T/p1_bytes_global.const.err"
  "$CC" build "$src" >/dev/null 2>"$err"
  rc=$?
  if [ "$rc" = 1 ] && grep -qF "CONST module-level global initialized by a runtime CALL returning an aggregate" "$err"; then
    echo "ok   p1_bytes_global: const path keeps its located reject"
  else
    echo "FAIL p1_bytes_global: const rc=$rc diagnostic=$(cat "$err" 2>/dev/null)"; fail=1
  fi

  mutsrc="$T/p1_bytes_global_mut.al"
  mutout="$T/p1_bytes_global_mut.out"
  rm -f "$mutout"
  cat >"$mutsrc" <<'EOF'
build := fn() -> [u8; 4] {
  mut t : [u8; 4] = [0; 4]
  t[2] = 42
  t
}
mut MG : [u8; 4] = build()
main := fn() -> u64 { u64(MG[2]) }
EOF
  "$CC" -o "$mutout" "$mutsrc" >/dev/null 2>"$T/p1_bytes_global.mut.err"
  rc=$?
  if [ "$rc" = 1 ] && [ ! -e "$mutout" ] && grep -qF "indexed read of a module-level [u8;N] global initialized by a runtime CALL" "$T/p1_bytes_global.mut.err"; then
    echo "ok   p1_bytes_global: mutable indexed-read guard is located"
  else
    echo "FAIL p1_bytes_global: mutable rc=$rc artifact=$(test -e "$mutout" && echo yes || echo no) diagnostic=$(cat "$T/p1_bytes_global.mut.err" 2>/dev/null)"; fail=1
  fi
}

# Types §1/§4.1 + Modules §2 — a module-qualified type is a comptime type value whose identity includes
# its module path. Exercise the package shape from codec proposal #6, plus a same-tail decoy with a
# different layout: Result's size/payload lowering must use codec::Error rather than a same-tail type.
qualified_generic_package_test() {
  p="$(_fixture_tree package)/qualified_generic_arg"
  rm -rf "$p/target"
  ( cd "$p" && "$CC" check package.al ) >/dev/null 2>&1; got=$?
  if [ "$got" = 0 ]; then echo "ok   qualified_generic_package: check 0"; else echo "FAIL qualified_generic_package: check got $got want 0"; fail=1; return; fi
  _e2e_exec_in "$p" "$CC" run package.al >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "qualified_generic_package(run)" "$got"; then return; fi
  if [ "$got" = 42 ]; then echo "ok   qualified_generic_package: run 42"; else echo "FAIL qualified_generic_package: run got $got want 42"; fail=1; return; fi
  rm -rf "$p/target"
  ( cd "$p" && "$CC" build package.al ) >/dev/null 2>&1 || { echo "FAIL qualified_generic_package: build"; fail=1; return; }
exe="$p/target/debug/qualified-generic-arg"
  _e2e_exec "$exe" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "qualified_generic_package(artifact)" "$got"; then return; fi
  if [ "$got" = 42 ]; then echo "ok   qualified_generic_package: artifact 42"; else echo "FAIL qualified_generic_package: artifact got $got want 42"; fail=1; fi
  rm -rf "$p/target"
}

## Issue #11, bounded Slice 3a — an unknown bare nominal type in a function parameter or return
## annotation must be refused before body checking or backend emission. The positive controls keep
## ordinary scalar signatures and abstract generic type parameters admissible; all cases are generated
## in the row-private scratch tree so this front-end boundary does not enter the four-backend oracle.
issue11_signature_type_name_test() {
  d="$T/issue11_signature_type"
  rm -rf "$d"
  mkdir -p "$d"
  printf '%s\n' 'take := fn(t : Nope) -> u64 { return 1 }' 'main := fn() -> u64 { return 42 }' > "$d/bad_param.al"
  printf '%s\n' 'give := fn() -> Nope { return 0 }' 'main := fn() -> u64 { return 42 }' > "$d/bad_return.al"
  printf '%s\n' 'take := fn(t : u64) -> u64 { return t }' 'main := fn() -> u64 { return take(42) }' > "$d/control.al"
  printf '%s\n' 'id := fn(T : type, x : T) -> T { return x }' 'main := fn() -> u64 { return id(u64, 42) }' > "$d/generic.al"

  for name in bad_param bad_return; do
    src="$d/$name.al"
    out="$d/$name.bin"
    err="$d/$name.check.err"
    "$CC" check "$src" >"$d/$name.check.out" 2>"$err"
    rc=$?
    if [ "$rc" = 1 ] && [ ! -s "$d/$name.check.out" ] && grep -qF "invalid at line 1 in $name" "$err"; then
      echo "ok   issue11_signature_type_name/$name: check rejects unknown signature type"
    else
      echo "FAIL issue11_signature_type_name/$name: check rc=$rc diagnostic=$(cat "$err" 2>/dev/null)"
      fail=1
    fi
    rm -f "$out"
    "$CC" -o "$out" "$src" >"$d/$name.build.out" 2>"$d/$name.build.err"
    rc=$?
    if [ "$rc" = 1 ] && [ ! -e "$out" ] && grep -qF "invalid at line 1 in $name" "$d/$name.build.err"; then
      echo "ok   issue11_signature_type_name/$name: build rejects without artifact"
    else
      echo "FAIL issue11_signature_type_name/$name: build rc=$rc artifact=$(test -e "$out" && echo yes || echo no) diagnostic=$(cat "$d/$name.build.err" 2>/dev/null)"
      fail=1
    fi
  done

  for name in control generic; do
    src="$d/$name.al"
    out="$d/$name.bin"
    "$CC" check "$src" >"$d/$name.check.out" 2>"$d/$name.check.err"
    rc=$?
    if [ "$rc" = 0 ] && [ ! -s "$d/$name.check.err" ]; then
      echo "ok   issue11_signature_type_name/$name: check accepts control"
    else
      echo "FAIL issue11_signature_type_name/$name: check rc=$rc diagnostic=$(cat "$d/$name.check.err" 2>/dev/null)"
      fail=1
    fi
    rm -f "$out"
    "$CC" -o "$out" "$src" >"$d/$name.build.out" 2>"$d/$name.build.err"
    rc=$?
    if [ "$rc" = 0 ] && [ -x "$out" ] && [ ! -s "$d/$name.build.err" ]; then
      _e2e_exec "$out" >/dev/null 2>&1; got=$?
      if _e2e_runtime_failure "issue11_signature_type_name/$name" "$got"; then return; fi
      if [ "$got" = 42 ]; then echo "ok   issue11_signature_type_name/$name: artifact runs 42"; else echo "FAIL issue11_signature_type_name/$name: artifact=$got want 42"; fail=1; fi
    else
      echo "FAIL issue11_signature_type_name/$name: build rc=$rc artifact=$(test -x "$out" && echo yes || echo no) diagnostic=$(cat "$d/$name.build.err" 2>/dev/null)"
      fail=1
    fi
  done
  rm -rf "$d"
}

## Issue #11, first bounded slice / Modules §3 + Types §6.4 — an undeclared direct type name in a
## package-owned nested module must be refused before either `check` or `build` emits an artifact.
## The same package shape with an ancestor-declared type stays green; the existing single-file type
## builtin fixture is also exercised here so this package-only boundary cannot regress it.
issue11_package_type_name_test() {
  bad="$T/issue11_undeclared_type"
  good="$T/issue11_declared_type"
  rm -rf "$bad" "$good"
  mkdir -p "$bad/src/geo" "$good/src/geo"
  cat > "$bad/package.al" <<'EOF'
app := Package(
  version = "0.1.0",
  source_dir = "src",
  target_dir = "target",
  targets = [
    Target(
      arch = Arch.x86_64,
      os = Os.linux,
      env = Env.gnu,
      container = Container.elf,
      output = "issue11-undeclared-type",
    ),
  ],
)
EOF
  cat > "$bad/src/main.al" <<'EOF'
main := fn() -> u64 {
  return geo::child::probe()
}
EOF
  cat > "$bad/src/geo/child.al" <<'EOF'
pub probe := fn() -> u64 {
  return size(Nope)
}
EOF
  cat > "$good/package.al" <<'EOF'
app := Package(
  version = "0.1.0",
  source_dir = "src",
  target_dir = "target",
  targets = [
    Target(
      arch = Arch.x86_64,
      os = Os.linux,
      env = Env.gnu,
      container = Container.elf,
      output = "issue11-declared-type",
    ),
  ],
)
EOF
  cat > "$good/src/main.al" <<'EOF'
main := fn() -> u64 {
  return geo::child::probe()
}
EOF
  cat > "$good/src/geo.al" <<'EOF'
Box := struct { a : u64, b : u64 }
EOF
  cat > "$good/src/geo/child.al" <<'EOF'
pub probe := fn() -> u64 {
  return size(Box) + 26
}
EOF
  for p in "$bad" "$good"; do
    [ -f "$p/package.al" ] || { echo "MISS issue11_package_type_name: $p/package.al"; fail=1; return; }
  done

  rm -rf "$bad/target"
  err="$T/issue11-package.check.err"
  ( cd "$bad" && "$CC" check package.al ) >/dev/null 2>"$err"
  rc=$?
  if [ "$rc" = 1 ] && [ ! -e "$bad/target/debug/issue11-undeclared-type" ] \
      && grep -qF "invalid at line 2 in geo__child" "$err"; then
    echo "ok   issue11_package_type_name: check rejects undeclared package type with location"
  else
    echo "FAIL issue11_package_type_name: check rc=$rc artifact=$(test -e "$bad/target/debug/issue11-undeclared-type" && echo yes || echo no) diagnostic=$(cat "$err" 2>/dev/null)"
    fail=1
  fi

  rm -rf "$bad/target"
  err="$T/issue11-package.build.err"
  ( cd "$bad" && "$CC" build package.al ) >/dev/null 2>"$err"
  rc=$?
  if [ "$rc" = 1 ] && [ ! -e "$bad/target/debug/issue11-undeclared-type" ] \
      && grep -qF "invalid at line 2 in geo__child" "$err"; then
    echo "ok   issue11_package_type_name: build rejects undeclared package type without artifact"
  else
    echo "FAIL issue11_package_type_name: build rc=$rc artifact=$(test -e "$bad/target/debug/issue11-undeclared-type" && echo yes || echo no) diagnostic=$(cat "$err" 2>/dev/null)"
    fail=1
  fi

  rm -rf "$good/target"
  err="$T/issue11-package-control.check.err"
  ( cd "$good" && "$CC" check package.al ) >/dev/null 2>"$err"
  rc=$?
  if [ "$rc" = 0 ] && [ ! -s "$err" ]; then
    echo "ok   issue11_package_type_name: declared package control passes check"
  else
    echo "FAIL issue11_package_type_name: declared package check rc=$rc diagnostic=$(cat "$err" 2>/dev/null)"
    fail=1
  fi

  rm -rf "$good/target"
  err="$T/issue11-package-control.build.err"
  ( cd "$good" && "$CC" build package.al ) >/dev/null 2>"$err"
  build_rc=$?
  exe="$good/target/debug/issue11-declared-type"
  summary='built: profile=debug target=x86_64-linux-gnu-elf artifact=target/debug/issue11-declared-type'
  if [ "$build_rc" = 0 ] && [ -x "$exe" ] && [ "$(cat "$err")" = "$summary" ] \
      && [ "$(wc -l <"$err")" = 1 ]; then
    _e2e_exec "$exe" >/dev/null 2>&1; got=$?
    if _e2e_runtime_failure "issue11_package_type_name/control" "$got"; then return; fi
    if [ "$got" = 42 ]; then echo "ok   issue11_package_type_name: declared package control artifact runs 42"; else echo "FAIL issue11_package_type_name: declared package artifact=$got want 42"; fail=1; fi
  else
    echo "FAIL issue11_package_type_name: declared package build rc=$build_rc artifact=$(test -x "$exe" && echo yes || echo no) diagnostic=$(cat "$err" 2>/dev/null)"
    fail=1
  fi
  rm -rf "$good/target" "$bad/target"

  single="$E2E_TEST/size_type_arg.al"
  err="$T/issue11-single.check.err"
  "$CC" check "$single" >/dev/null 2>"$err"
  rc=$?
  if [ "$rc" = 0 ] && [ ! -s "$err" ]; then
    echo "ok   issue11_package_type_name: existing single-file type-builtin control passes check"
  else
    echo "FAIL issue11_package_type_name: single-file check rc=$rc diagnostic=$(cat "$err" 2>/dev/null)"
    fail=1
  fi
  out="$T/issue11-single.out"
  rm -f "$out"
  err="$T/issue11-single.build.err"
  "$CC" -o "$out" "$single" >/dev/null 2>"$err"
  rc=$?
  if [ "$rc" = 0 ] && [ -x "$out" ] && [ ! -s "$err" ]; then
    _e2e_exec "$out" >/dev/null 2>&1; got=$?
    if _e2e_runtime_failure "issue11_package_type_name/single-file" "$got"; then return; fi
    if [ "$got" = 42 ]; then echo "ok   issue11_package_type_name: existing single-file artifact runs 42"; else echo "FAIL issue11_package_type_name: single-file artifact=$got want 42"; fail=1; fi
  else
    echo "FAIL issue11_package_type_name: single-file build rc=$rc artifact=$(test -x "$out" && echo yes || echo no) diagnostic=$(cat "$err" 2>/dev/null)"
    fail=1
  fi
}

## Types §6.1 / Modules §3 — the standard-byte tuple global fence must inspect the CURRENT declaration,
## not a same-named global from another module. Generate two disposable packages with opposite source
## orders so a bare-name recovery either misses the byte global or reports the ordinary one. The fixture
## is row-local (not part of the corpus): this is a source-location/module-identity probe for `check`.
standard_tuple_global_module_test() {
  root="$T/e2e_standard_tuple_global_modules"
  rm -rf "$root"
  mkdir -p "$root/forward/src" "$root/reverse/src"
  for p in "$root/forward" "$root/reverse"; do
    cat > "$p/package.al" <<'EOF'
app := Package(
  version = "0.1.0",
  source_dir = "src",
  target_dir = "target",
  targets = [Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf, entry = "_start", output = "standard-tuple-global-modules")],
)
EOF
    cat > "$p/src/main.al" <<'EOF'
_start := fn() { exit(42) }
EOF
  done
  cat > "$root/forward/src/a_byte.al" <<'EOF'
pub mut G : ([u8; 4], u64) = ([1, 2, 3, 4], 9)
EOF
  cat > "$root/forward/src/z_word.al" <<'EOF'
pub mut G : (u64, u64) = (7, 8)
EOF
  cat > "$root/reverse/src/a_word.al" <<'EOF'
pub mut G : (u64, u64) = (7, 8)
EOF
  cat > "$root/reverse/src/z_byte.al" <<'EOF'
pub mut G : ([u8; 4], u64) = ([1, 2, 3, 4], 9)
EOF
  multiline="$root/multiline.al"
  cat > "$multiline" <<'EOF'
## The same boundary with whitespace inside and around the tuple and array type.
mut G : (
	[u8;
	4],
	u64
) = ([1, 2, 3, 4], 9)

main := fn() -> u64 {
  G.0[1]
}
EOF
  err="$T/standard_tuple_global_multiline.check.err"
  "$CC" check "$multiline" >/dev/null 2>"$err"
  rc=$?
  if [ "$rc" = 1 ] && grep -qF "a standard-layout byte tuple global is not supported yet" "$err"; then
    echo "ok   standard_tuple_global/multiline: check rejected"
  else
    echo "FAIL standard_tuple_global/multiline: check rc=$rc diagnostic=$(cat "$err" 2>/dev/null)"
    fail=1
  fi
  rm -f "$root/multiline.out"
  "$CC" -o "$root/multiline.out" "$multiline" >/dev/null 2>"$T/standard_tuple_global_multiline.x86.err"
  rc=$?
  if [ "$rc" != 0 ] && [ ! -e "$root/multiline.out" ] && grep -qF "a standard-layout byte tuple global is not supported yet" "$T/standard_tuple_global_multiline.x86.err"; then
    echo "ok   standard_tuple_global/multiline: x86 build rejected before artifact"
  else
    echo "FAIL standard_tuple_global/multiline: x86 rc=$rc artifact=$(test -e "$root/multiline.out" && echo yes || echo no) diagnostic=$(cat "$T/standard_tuple_global_multiline.x86.err" 2>/dev/null)"
    fail=1
  fi
  for backend in wat aarch64 riscv64; do
    out="$root/multiline.$backend.out"
    err="$T/standard_tuple_global_multiline.$backend.err"
    "$CC" "$backend" "$multiline" >"$out" 2>"$err"
    rc=$?
    if [ "$rc" != 0 ] && [ ! -s "$out" ] && grep -qF "a standard-layout byte tuple global is not supported yet" "$err"; then
      echo "ok   standard_tuple_global/multiline: $backend rejected without emission"
    else
      echo "FAIL standard_tuple_global/multiline: $backend rc=$rc stdout=$(wc -c < "$out") diagnostic=$(cat "$err" 2>/dev/null)"
      fail=1
    fi
  done
  offset0="$root/offset0.al"
  cat > "$offset0" <<'EOF'
G : ([u8; 4], u64) = ([1, 2, 3, 4], 9)
main := fn() -> u64 { G.0[1] }
EOF
  err="$T/standard_tuple_global_offset0.check.err"
  "$CC" check "$offset0" >/dev/null 2>"$err"
  rc=$?
  if [ "$rc" = 1 ] && grep -qF "a standard-layout byte tuple global is not supported yet" "$err" && grep -qF "at line 1 in offset0" "$err"; then
    echo "ok   standard_tuple_global/offset0: check kept diagnostic and location"
  else
    echo "FAIL standard_tuple_global/offset0: check rc=$rc diagnostic=$(cat "$err" 2>/dev/null)"
    fail=1
  fi
  rm -f "$root/offset0.out"
  "$CC" -o "$root/offset0.out" "$offset0" >/dev/null 2>"$T/standard_tuple_global_offset0.x86.err"
  rc=$?
  if [ "$rc" != 0 ] && [ ! -e "$root/offset0.out" ] && grep -qF "a standard-layout byte tuple global is not supported yet" "$T/standard_tuple_global_offset0.x86.err"; then
    echo "ok   standard_tuple_global/offset0: x86 kept diagnostic"
  else
    echo "FAIL standard_tuple_global/offset0: x86 rc=$rc artifact=$(test -e "$root/offset0.out" && echo yes || echo no) diagnostic=$(cat "$T/standard_tuple_global_offset0.x86.err" 2>/dev/null)"
    fail=1
  fi
  for spec in "forward|a_byte" "reverse|z_byte"; do
    IFS='|' read -r name expected <<< "$spec"
    err="$T/standard_tuple_global_$name.err"
    ( cd "$root/$name" && "$CC" check package.al ) >/dev/null 2>"$err"
    rc=$?
    if [ "$rc" = 1 ] && grep -qF "a standard-layout byte tuple global is not supported yet" "$err" && grep -qF "in $expected" "$err"; then
      echo "ok   standard_tuple_global_module/$name: rejected current byte global in $expected"
    else
      echo "FAIL standard_tuple_global_module/$name: rc=$rc diagnostic=$(cat "$err" 2>/dev/null)"
      fail=1
    fi
  done
}

## Modules §1/§4 + Types §4.1 — same-named nominal enums must never let declaration order choose a
## variant layout. The fixture lives outside test/package because it is also part of the corpus; copy it
## into this row's private scratch before every build. Both unequal-count orders must preserve the
## callee module's enum identity and return 42, while equal-count and different-name controls still run 42.
ambig_enum_collision_test() {
  src="$E2E_TEST/ambig_enum_name_collision"
  d="$T/ambig_enum_name_collision"
  [ -d "$src" ] || { echo "FAIL ambig_enum_collision: fixture tree missing"; fail=1; return; }
  cp -r "$src" "$d" || { echo "FAIL ambig_enum_collision: could not snapshot fixture"; fail=1; return; }
  for name in failing reverse; do
    case "$name" in
      failing) output="ambig-enum-name-collision" ;;
      reverse) output="ambig-enum-name-collision-reverse" ;;
    esac
    p="$d/$name"
    ( cd "$p" && "$CC" check package.al ) >/dev/null 2>&1; rc=$?
    if [ "$rc" = 0 ]; then echo "ok   ambig_enum_collision/$name: check accepted"; else echo "FAIL ambig_enum_collision/$name: check rc=$rc"; fail=1; fi
    _e2e_exec_in "$p" "$CC" run package.al >/dev/null 2>&1; got=$?
    if _e2e_runtime_failure "ambig_enum_collision/$name(run)" "$got"; then return; fi
    if [ "$got" = 42 ]; then echo "ok   ambig_enum_collision/$name: run 42"; else echo "FAIL ambig_enum_collision/$name: run=$got want=42"; fail=1; fi
    rm -rf "$p/target"
    ( cd "$p" && "$CC" build package.al ) >/dev/null 2>&1; rc=$?
    if [ "$rc" != 0 ]; then echo "FAIL ambig_enum_collision/$name: build rc=$rc"; fail=1; continue; fi
    _e2e_exec "$p/target/debug/$output" >/dev/null 2>&1; got=$?
    if _e2e_runtime_failure "ambig_enum_collision/$name(artifact)" "$got"; then return; fi
    if [ "$got" = 42 ]; then echo "ok   ambig_enum_collision/$name: artifact 42"; else echo "FAIL ambig_enum_collision/$name: artifact=$got want=42"; fail=1; fi
  done
  for name in equal different; do
    case "$name" in
      equal) output="ambig-enum-equal-control" ;;
      different) output="ambig-enum-different-control" ;;
    esac
    p="$d/$name"
    ( cd "$p" && "$CC" check package.al ) >/dev/null 2>&1; rc=$?
    if [ "$rc" = 0 ]; then echo "ok   ambig_enum_collision/$name: check accepted"; else echo "FAIL ambig_enum_collision/$name: check rc=$rc"; fail=1; fi
    _e2e_exec_in "$p" "$CC" run package.al >/dev/null 2>&1; got=$?
    if _e2e_runtime_failure "ambig_enum_collision/$name(run)" "$got"; then return; fi
    if [ "$got" = 42 ]; then echo "ok   ambig_enum_collision/$name: run 42"; else echo "FAIL ambig_enum_collision/$name: run=$got want=42"; fail=1; fi
    rm -rf "$p/target"
    ( cd "$p" && "$CC" build package.al ) >/dev/null 2>&1; rc=$?
    if [ "$rc" != 0 ]; then echo "FAIL ambig_enum_collision/$name: build rc=$rc"; fail=1; continue; fi
  _e2e_exec "$p/target/debug/$output" >/dev/null 2>&1; got=$?
    if _e2e_runtime_failure "ambig_enum_collision/$name(artifact)" "$got"; then return; fi
    if [ "$got" = 42 ]; then echo "ok   ambig_enum_collision/$name: artifact 42"; else echo "FAIL ambig_enum_collision/$name: artifact=$got want=42"; fail=1; fi
  done
}

## Modules §2/§3 + Types §4.1 — a qualified type path must keep its module head even when the parser
## hands the type consumer only the tail Expr::Var span. `codec::Error` must stay nominal when a second
## `pub Error` exists, regardless of source order; the single-module package is the control. These
## fixtures live outside test/package so the full corpus also visits every package/source file.
ambig_pub_test() {
  src="$E2E_TEST/ambig_pub"
  d="$T/ambig_pub"
  [ -d "$src" ] || { echo "FAIL ambig_pub: fixture tree missing"; fail=1; return; }
  cp -r "$src" "$d" || { echo "FAIL ambig_pub: could not snapshot fixture"; fail=1; return; }
  for name in single forward reverse; do
    case "$name" in
      single) output="ambig-pub-single" ;;
      forward) output="ambig-pub-forward" ;;
      reverse) output="ambig-pub-reverse" ;;
    esac
    p="$d/$name"
    ( cd "$p" && "$CC" check package.al ) >/dev/null 2>&1; rc=$?
    if [ "$rc" = 0 ]; then echo "ok   ambig_pub/$name: check accepted"; else echo "FAIL ambig_pub/$name: check rc=$rc"; fail=1; fi
    _e2e_exec_in "$p" "$CC" run package.al >/dev/null 2>&1; got=$?
    if _e2e_runtime_failure "ambig_pub/$name(run)" "$got"; then return; fi
    if [ "$got" = 42 ]; then echo "ok   ambig_pub/$name: run 42"; else echo "FAIL ambig_pub/$name: run=$got want=42"; fail=1; fi
    rm -rf "$p/target"
    ( cd "$p" && "$CC" build package.al ) >/dev/null 2>&1; rc=$?
    if [ "$rc" != 0 ]; then echo "FAIL ambig_pub/$name: build rc=$rc"; fail=1; continue; fi
    _e2e_exec "$p/target/debug/$output" >/dev/null 2>&1; got=$?
    if _e2e_runtime_failure "ambig_pub/$name(artifact)" "$got"; then return; fi
    if [ "$got" = 42 ]; then echo "ok   ambig_pub/$name: artifact 42"; else echo "FAIL ambig_pub/$name: artifact=$got want=42"; fail=1; fi
  done
}

# Manifest §140 — a package-aware command with no path argument AND no ./package.al is an input
# error reported located, never a doomed link (before, `check`/`test` returned a SILENT 0).
no_input_diag_test() {
  ## This directory must not live below the checkout: TOOL-14 deliberately discovers an ancestor
  ## package.al, so `$T/e2e_no_input` would be a package invocation rather than a no-input case.
  d=$(mktemp -d /tmp/alatyr-e2e-no-input.XXXXXX) || { echo "FAIL no_input_diag: mktemp"; fail=1; return; }
  for c in run build check test; do
    if [ "$c" = run ] || [ "$c" = test ]; then
      out_file="$T/no_input_$c.err"
      _e2e_exec_in "$d" "$CC" "$c" >/dev/null 2>"$out_file"; got=$?
      out="$(<"$out_file")"
      if _e2e_runtime_failure "no_input_diag($c)" "$got"; then rm -rf "$d"; return; fi
    else
      out=$( cd "$d" && "$CC" "$c" 2>&1 >/dev/null ); got=$?
    fi
    if [ "$got" = 40 ] && case "$out" in "alatyr: $c: config: no discoverable package.al and no file list (searched upward from "*) true ;; *) false ;; esac; then
      echo "ok   no_input_diag($c): rc 40 + located diagnostic"
    else
      echo "FAIL no_input_diag($c): rc=$got out=$out"; fail=1
    fi
  done
  rm -rf "$d"
}

## TOOL-16 / Tooling §2.6 — vendoring is post-v1: an unknown manifest field and the removed CLI flag
## are Config diagnostics. The control source path must remain an ordinary bare-file input, and a
## missing option argument must not be mistaken for that input.
tool16_no_vendor_test() {
  bad="$E2E_TEST/package/tool16_no_vendor"
  good="$bad/control"
  ( cd "$bad" && "$CC" build package.al >/dev/null 2>"$T/tool16-manifest.err" ); rc=$?
  if [ "$rc" = 1 ] && grep -Fq "config: Package field vendor_dir is not supported in v1" "$T/tool16-manifest.err"; then
    echo "ok   tool16_no_vendor/manifest: Config rejection"
  else
    echo "FAIL tool16_no_vendor/manifest: rc=$rc"; fail=1
  fi
  ( cd "$good" && "$CC" build --vendor-dir /tmp/vendor package.al >/dev/null 2>"$T/tool16-cli.err" ); rc=$?
  if [ "$rc" = 40 ] && grep -Fq "alatyr: config: --vendor-dir is not supported in v1" "$T/tool16-cli.err"; then
    echo "ok   tool16_no_vendor/cli: Config rejection"
  else
    echo "FAIL tool16_no_vendor/cli: rc=$rc"; fail=1
  fi
  ( cd "$good" && "$CC" build --vendor-dir >/dev/null 2>"$T/tool16-missing.err" ); rc=$?
  if [ "$rc" = 40 ] && grep -Fq "alatyr: config: an option is missing its argument" "$T/tool16-missing.err"; then
    echo "ok   tool16_no_vendor/missing: Config rejection"
  else
    echo "FAIL tool16_no_vendor/missing: rc=$rc"; fail=1
  fi
  "$CC" build "$good/src/main.al" >/dev/null 2>&1; rc=$?
  if [ "$rc" = 0 ]; then
    echo "ok   tool16_no_vendor/source-path: ordinary source path accepted"
  else
    echo "FAIL tool16_no_vendor/source-path: rc=$rc"; fail=1
  fi
  rm -rf "$good/target" "$bad/target"
}

## TOOL-11 / Tooling §2.2 + Manifest §3.2 — explicit Target.output is a file name, never a path;
## omitted output remains valid through the normal defaulting path.
tool11_output_validation_test() {
  d="$E2E_TEST/package/tool11_output_validation"
  for name in package.al slash/package.al backslash/package.al; do
    p="$d/$name"
    tag=${name%/*}; tag=${tag##*/}; [ "$tag" = "package.al" ] && tag=empty
    ( cd "$(dirname "$p")" && "$CC" build "$(basename "$p")" >/dev/null 2>"$T/tool11-$tag.err" ); rc=$?
    if [ "$rc" = 1 ] && grep -Fq "config: Target.output must be a non-empty file name without path separators" "$T/tool11-$tag.err"; then
      echo "ok   tool11_output_validation/$name: located Config rejection"
    else
      echo "FAIL tool11_output_validation/$name: rc=$rc"; fail=1
    fi
  done
  ( cd "$d/control" && "$CC" build package.al >/dev/null 2>"$T/tool11-control.err" ); rc=$?
  if [ "$rc" = 0 ] && [ -x "$d/control/target/debug/a.out" ]; then
    _e2e_exec "$d/control/target/debug/a.out" >/dev/null 2>&1; got=$?
    if _e2e_runtime_failure "tool11_output_validation/omitted" "$got"; then return; fi
    if [ "$got" = 42 ]; then echo "ok   tool11_output_validation/omitted: default output accepted"; else echo "FAIL tool11_output_validation/omitted: artifact=$got"; fail=1; fi
  else
    echo "FAIL tool11_output_validation/omitted: rc=$rc"; fail=1
  fi
  rm -rf "$d/target" "$d/slash/target" "$d/backslash/target"
  rm -rf "$d/control/target"
}

## TOOL-13 / Tooling §2.6 + Manifest §3.8 — explicit package source/target directories are lexical,
## package-local paths. The negative controls check the exact located Config message; the two positive
## controls keep the explicit src/target layout and the omitted-source spec default `src` layout.
tool13_path_validation_test() {
  d="$E2E_TEST/package/tool13_path_validation"
  cases=(
    "source_absolute|config: Package.source_dir must be relative and remain inside package root|2"
    "source_escape|config: Package.source_dir must be relative and remain inside package root|2"
    "target_absolute|config: Package.target_dir must be relative and remain inside package root|3"
    "target_escape|config: Package.target_dir must be relative and remain inside package root|3"
    "source_root|config: Package.source_dir must not contain the manifest file or package root|2"
    "source_target|config: Package.source_dir must not contain target_dir|2"
    "source_target_alias|config: Package.source_dir must not contain target_dir|2"
    "default_source_target|config: Package.target_dir must not be inside source_dir|3"
  )
  for spec in "${cases[@]}"; do
    IFS='|' read -r name needle line <<< "$spec"
    err="$T/tool13-$name.err"
    ( cd "$d/$name" && "$CC" build package.al >/dev/null 2>"$err" ); rc=$?
    expected="$needle at line $line in package.al"
    if [ "$rc" = 1 ] && grep -Fq "$expected" "$err"; then
      echo "ok   tool13_path_validation/$name: located Config rejection"
    else
      echo "FAIL tool13_path_validation/$name: rc=$rc diagnostic=$(cat "$err" 2>/dev/null)"; fail=1
    fi
  done
  p="$d/control"
  ( cd "$p" && "$CC" build package.al >/dev/null 2>"$T/tool13-control.err" ); rc=$?
  if [ "$rc" = 0 ] && [ -x "$p/target/debug/tool13-control" ]; then
    _e2e_exec "$p/target/debug/tool13-control" >/dev/null 2>&1; got=$?
    if _e2e_runtime_failure "tool13_path_validation/control" "$got"; then return; fi
    if [ "$got" = 42 ]; then echo "ok   tool13_path_validation/control: explicit src/target accepted"; else echo "FAIL tool13_path_validation/control: artifact=$got"; fail=1; fi
  else
    echo "FAIL tool13_path_validation/control: rc=$rc"; fail=1
  fi
  p="$d/default_src"
  ( cd "$p" && "$CC" build package.al >/dev/null 2>"$T/tool13-default.err" ); rc=$?
  if [ "$rc" = 0 ] && [ -x "$p/target/debug/a.out" ]; then
    _e2e_exec "$p/target/debug/a.out" >/dev/null 2>&1; got=$?
    if _e2e_runtime_failure "tool13_path_validation/default" "$got"; then return; fi
    if [ "$got" = 42 ]; then echo "ok   tool13_path_validation/default: omitted source_dir uses src layout"; else echo "FAIL tool13_path_validation/default: artifact=$got"; fail=1; fi
    if nm "$p/target/debug/a.out" 2>/dev/null | grep -qE ' T tool13_outside_default_probe$'; then
      echo "FAIL tool13_path_validation/default: root-level outside module was discovered"; fail=1
    else
      echo "ok   tool13_path_validation/default: root-level module excluded from src layout"
    fi
  else
    echo "FAIL tool13_path_validation/default: rc=$rc"; fail=1
  fi
  rm -rf "$d"/*/target
}

## TOOL-13 / Tooling §2.6 — when a manifest declares multiple targets, the selected target name is part
## of the artifact root. Debug/release/test artifacts share that stable root, and --target selects the
## requested record instead of silently building the first one.
multi_target_layout_test() {
  p="$(_fixture_tree package)/multi_target_layout"
  rm -rf "$p/target"
  ( cd "$p" && "$CC" build package.al ) >/dev/null 2>&1 || { echo "FAIL multi_target_layout: debug build"; fail=1; return; }
  out="$p/target/host/debug/multi-host"
  if [ -x "$out" ] && [ ! -e "$p/target/debug/multi-host" ]; then
    _e2e_exec "$out" >/dev/null 2>&1; got=$?
    if _e2e_runtime_failure "multi_target_layout(debug)" "$got"; then return; fi
    if [ "$got" = 42 ]; then echo "ok   multi_target_layout: debug artifact host/debug 42"; else echo "FAIL multi_target_layout: debug artifact exit=$got want=42"; fail=1; fi
  else
    echo "FAIL multi_target_layout: debug artifact path"; fail=1
  fi
  rm -rf "$p/target"
  ( cd "$p" && "$CC" build --release package.al ) >/dev/null 2>&1 || { echo "FAIL multi_target_layout: release build"; fail=1; return; }
  out="$p/target/host/release/multi-host"
  if [ -x "$out" ]; then
    _e2e_exec "$out" >/dev/null 2>&1; got=$?
    if _e2e_runtime_failure "multi_target_layout(release)" "$got"; then return; fi
    if [ "$got" = 42 ]; then echo "ok   multi_target_layout: release artifact host/release 42"; else echo "FAIL multi_target_layout: release artifact exit=$got want=42"; fail=1; fi
  else
    echo "FAIL multi_target_layout: release artifact path"; fail=1
  fi
  rm -rf "$p/target"
  ( cd "$p" && "$CC" build --target all package.al ) >"$T/multi_target_layout.all.out" 2>"$T/multi_target_layout.all.err"
  rc=$?
  host="$p/target/host/debug/multi-host"
  alternate="$p/target/alternate/debug/multi-alternate"
  host_rc=127
  alternate_rc=127
  if [ -x "$host" ]; then _e2e_exec "$host" >/dev/null 2>&1; host_rc=$?; fi
  if [ -x "$alternate" ]; then _e2e_exec "$alternate" >/dev/null 2>&1; alternate_rc=$?; fi
  if _e2e_runtime_failure "multi_target_layout(all host)" "$host_rc"; then return; fi
  if _e2e_runtime_failure "multi_target_layout(all alternate)" "$alternate_rc"; then return; fi
  summary="$T/multi_target_layout.all.summary"
  printf '%s\n%s\n' \
    'built: profile=debug target=x86_64-linux-gnu-elf artifact=target/host/debug/multi-host' \
    'built: profile=debug target=x86_64-linux-gnu-elf artifact=target/alternate/debug/multi-alternate' >"$summary"
  if [ "$rc" = 0 ] && [ "$host_rc" = 42 ] && [ "$alternate_rc" = 42 ] \
    && [ -s "$host.s" ] && [ -s "$host.o" ] \
    && [ -s "$alternate.s" ] && [ -s "$alternate.o" ] \
    && [ ! -e "$p/target/debug/multi-host" ] && [ ! -e "$p/target/debug/multi-alternate" ] \
    && cmp -s "$T/multi_target_layout.all.err" "$summary"; then
    echo "ok   multi_target_layout: --target all builds host and alternate without intermediate collisions"
  else
    echo "FAIL multi_target_layout: --target all rc=$rc host=$host_rc alternate=$alternate_rc or target-qualified artifacts/summary missing"; fail=1
  fi
  rm -rf "$p/target"
  bad="$T/multi_target_layout_bad_output"
  cp -r "$p" "$bad"
  sed -i 's/output = "multi-alternate"/output = "bad\/name"/' "$bad/package.al"
  ( cd "$bad" && "$CC" build --target all package.al ) >"$T/multi_target_layout.bad_output.out" 2>"$T/multi_target_layout.bad_output.err"
  rc=$?
  if [ "$rc" != 0 ] && grep -qF 'config: Target.output must be a non-empty file name without path separators' "$T/multi_target_layout.bad_output.err" \
    && [ ! -e "$bad/target" ]; then
    echo "ok   multi_target_layout: --target all validates every target before dispatch"
  else
    echo "FAIL multi_target_layout: invalid later target rc=$rc partial=$(test -e "$bad/target" && find "$bad/target" -type f | head -1 || echo no)"; fail=1
  fi
  rm -rf "$bad"
  ( cd "$p" && "$CC" -o "$p/custom/multi" --target all package.al ) >"$T/multi_target_layout.o_all.out" 2>"$T/multi_target_layout.o_all.err"
  rc=$?
  if [ "$rc" != 0 ] && grep -qF 'config:' "$T/multi_target_layout.o_all.err" \
    && [ ! -e "$p/custom/multi" ] && [ ! -e "$p/target" ]; then
    echo "ok   multi_target_layout: -o with --target all rejects before artifact creation"
  else
    echo "FAIL multi_target_layout: -o with --target all rc=$rc artifact=$(test -e "$p/custom/multi" && echo yes || echo no) target=$(test -e "$p/target" && echo yes || echo no)"; fail=1
  fi
  rm -rf "$p/target" "$p/custom"
  _e2e_exec_capture_in "$T/multi_target_layout.test.out" "$p" "$CC" test package.al \
    2>"$T/multi_target_layout.test.err"
  rc=$?
  if _e2e_runtime_failure "multi_target_layout(test)" "$rc"; then rm -rf "$p/target"; return; fi
  if [ "$rc" = 0 ] && grep -qF 'alatyr test: 0 tests' "$T/multi_target_layout.test.out" \
    && [ -x "$p/target/host/debug/multi-host.test" ] \
    && [ ! -e "$p/target/debug/multi-host.test" ]; then
    echo "ok   multi_target_layout: test artifact host/debug";
  else
    echo "FAIL multi_target_layout: test rc=$rc or artifact path"; fail=1
  fi
  rm -rf "$p/target"
  ( cd "$p" && "$CC" build --target alternate package.al ) >"$T/multi_target_layout.alternate.out" 2>"$T/multi_target_layout.alternate.err"
  rc=$?
  out="$p/target/alternate/debug/multi-alternate"
  if [ "$rc" = 0 ] && [ -x "$out" ]; then
    _e2e_exec "$out" >/dev/null 2>&1; got=$?
    if _e2e_runtime_failure "multi_target_layout(alternate)" "$got"; then return; fi
    if [ "$got" = 42 ]; then echo "ok   multi_target_layout: --target alternate selects alternate/debug"; else echo "FAIL multi_target_layout: alternate exit=$got want=42"; fail=1; fi
  else
    echo "FAIL multi_target_layout: --target alternate rc=$rc or artifact path"; fail=1
  fi
  rm -rf "$p/target"
  ( cd "$p" && "$CC" build --target missing package.al ) >"$T/multi_target_layout.target.out" 2>"$T/multi_target_layout.target.err"
  rc=$?
  if [ "$rc" = 1 ] && grep -qF 'config: --target names no Target in the manifest at line 5 in package.al' "$T/multi_target_layout.target.err" \
    && [ ! -e "$p/target" ]; then
    echo "ok   multi_target_layout: unknown --target is located Config reject"
  else
    echo "FAIL multi_target_layout: --target rc=$rc diagnostic=$(cat "$T/multi_target_layout.target.err" 2>/dev/null)"; fail=1
  fi
  rm -rf "$p/target"
}

## TOOL-17 / Tooling §4 — a source target is a valid input to `check`: configuration, parsing and
## semantics are validated without an artifact-producing kind. The same manifest remains a located
## unsupported-kind reject for `build`; keep the two package fixtures separate so a target left by one
## command cannot make the other assertion vacuous.
tool17_source_check_test() {
  root="$(_fixture_tree package)/tool17_source_check"
  p="$root/positive"
  rm -rf "$p/target"
  ( cd "$p" && "$CC" check package.al ) >/dev/null 2>"$T/tool17_source_check.positive.err"
  rc=$?
  if [ "$rc" = 0 ] && [ ! -e "$p/target" ] && [ ! -s "$T/tool17_source_check.positive.err" ]; then
    echo "ok   tool17_source_check: Kind.source check accepted without target/"
  else
    echo "FAIL tool17_source_check: check rc=$rc target=$(test -e "$p/target" && echo yes || echo no)"
    fail=1
  fi
  p="$root/negative"
  rm -rf "$p/target"
  ( cd "$p" && "$CC" build package.al ) >/dev/null 2>"$T/tool17_source_check.negative.err"
  rc=$?
  if [ "$rc" = 42 ] && [ ! -e "$p/target" ] \
    && grep -qF 'config: Target.kind = Kind.source is not implemented yet at line 10 in package.al' "$T/tool17_source_check.negative.err"; then
    echo "ok   tool17_source_check: build keeps located Kind.source reject"
  else
    echo "FAIL tool17_source_check: build rc=$rc target=$(test -e "$p/target" && echo yes || echo no) diagnostic=$(cat "$T/tool17_source_check.negative.err" 2>/dev/null)"
    fail=1
  fi
  rm -rf "$root/positive/target" "$root/negative/target"
}

## TOOL-17 / Tooling §2.7 — `target.kind` is the selected artifact kind, not a hard-coded executable
## answer. The executable branch runs; object/static_lib branches are checked in their emitted GAS
## before assembly/archive; source is check-only; shared_lib is built as the released x86_64/Linux/ELF
## dynamic object. Each package is row-private through `_fixture_tree`, so artifact existence cannot
## leak between the assertions.
tool17_target_kind_test() {
  root="$(_fixture_tree package)/tool17_target_kind"
  p="$root/red"
  rm -rf "$p/target"
  ( cd "$p" && "$CC" build package.al ) >/dev/null 2>"$T/tool17_target_kind.red.err"
  rc=$?
  bin="$p/target/debug/tool17-kind-red"
  if [ "$rc" = 0 ] && [ -x "$bin" ]; then
    _e2e_exec "$bin" >/dev/null 2>&1; got=$?
    if _e2e_runtime_failure "tool17_target_kind" "$got"; then return; fi
    if [ "$got" = 42 ]; then echo "ok   tool17_target_kind: executable ==/!= folds and runs 42"; else echo "FAIL tool17_target_kind: executable exit=$got want 42"; fail=1; fi
  else
    echo "FAIL tool17_target_kind: executable build rc=$rc diagnostic=$(cat "$T/tool17_target_kind.red.err" 2>/dev/null)"; fail=1
  fi

  p="$root/object"
  rm -rf "$p/target"
  ( cd "$p" && "$CC" build package.al ) >/dev/null 2>"$T/tool17_target_kind.object.err"
  rc=$?
  obj="$p/target/debug/tool17-kind-object.o"
  objs="$obj.s"
  if [ "$rc" = 0 ] && [ -f "$obj" ] && nm "$obj" 2>/dev/null | grep -qE ' T api__probe$' \
    && grep -qF 'movq $20' "$objs" && grep -qF 'movq $22' "$objs" \
    && ! grep -qF 'movq $200' "$objs" && ! grep -qF 'movq $220' "$objs"; then
    echo "ok   tool17_target_kind: object ==/!= selected object branch"
  else
    echo "FAIL tool17_target_kind: object rc=$rc artifact=$obj diagnostic=$(cat "$T/tool17_target_kind.object.err" 2>/dev/null)"; fail=1
  fi

  p="$root/static_lib"
  rm -rf "$p/target"
  ( cd "$p" && "$CC" build package.al ) >/dev/null 2>"$T/tool17_target_kind.static.err"
  rc=$?
  lib="$p/target/debug/libtool17-kind.a"
  libs="$p/target/debug/libtool17-kind.a.o.s"
  if [ "$rc" = 0 ] && [ -f "$lib" ] && ar t "$lib" 2>/dev/null | grep -qF 'libtool17-kind.a.o' \
    && grep -qF 'movq $20' "$libs" && grep -qF 'movq $22' "$libs" \
    && ! grep -qF 'movq $200' "$libs" && ! grep -qF 'movq $220' "$libs"; then
    echo "ok   tool17_target_kind: static_lib ==/!= selected archive branch"
  else
    echo "FAIL tool17_target_kind: static_lib rc=$rc artifact=$lib diagnostic=$(cat "$T/tool17_target_kind.static.err" 2>/dev/null)"; fail=1
  fi

  p="$root/source"
  rm -rf "$p/target"
  ( cd "$p" && "$CC" check package.al ) >/dev/null 2>"$T/tool17_target_kind.source.check.err"
  rc=$?
  if [ "$rc" = 0 ] && [ ! -e "$p/target" ] && [ ! -s "$T/tool17_target_kind.source.check.err" ]; then
    echo "ok   tool17_target_kind: source check folds without artifact"
  else
    echo "FAIL tool17_target_kind: source check rc=$rc target=$(test -e "$p/target" && echo yes || echo no)"; fail=1
  fi
  ( cd "$p" && "$CC" build package.al ) >/dev/null 2>"$T/tool17_target_kind.source.build.err"
  rc=$?
  if [ "$rc" = 42 ] && [ ! -e "$p/target" ] \
    && grep -qF 'config: Target.kind = Kind.source is not implemented yet at line 10 in package.al' "$T/tool17_target_kind.source.build.err"; then
    echo "ok   tool17_target_kind: source build keeps located reject"
  else
    echo "FAIL tool17_target_kind: source build rc=$rc diagnostic=$(cat "$T/tool17_target_kind.source.build.err" 2>/dev/null)"; fail=1
  fi

  p="$root/shared_lib"
  rm -rf "$p/target"
  ( cd "$p" && "$CC" build package.al ) >/dev/null 2>"$T/tool17_target_kind.shared.err"
  rc=$?
  lib="$p/target/debug/libapp.so"
  if [ "$rc" = 0 ] && [ -f "$lib" ] \
    && readelf -h "$lib" 2>/dev/null | grep -qE 'Type:[[:space:]]+DYN[[:space:]]+\(Shared object file\)' \
    && nm -D "$lib" 2>/dev/null | grep -qE ' T api__probe$' \
    && ! nm "$lib" 2>/dev/null | grep -qE ' [Tt] _start$'; then
    echo "ok   tool17_target_kind: shared_lib emits default .so with pub surface and no entry"
  else
    echo "FAIL tool17_target_kind: shared_lib rc=$rc artifact=$lib diagnostic=$(cat "$T/tool17_target_kind.shared.err" 2>/dev/null)"; fail=1
  fi
  rm -rf "$root"/*/target
}

## TOOL-17 / Tooling §2.7 — publish the selected x86 Target.code_size (default b64 plus an explicit
## b32) through the cli → driver → ctfold boundary. Each source compares both equality and inequality
## against a different CodeSize variant; execute the generated artifact so a stale/default-only fold
## cannot satisfy the row.
tool17_target_code_size_test() {
  root="$(_fixture_tree package)/tool17_target_code_size"
  p="$root/default"
  rm -rf "$p/target"
  ( cd "$p" && "$CC" build package.al ) >/dev/null 2>"$T/tool17_target_code_size.default.err"
  rc=$?
  bin="$p/target/debug/code-size-default"
  if [ "$rc" = 0 ] && [ -x "$bin" ]; then
    _e2e_exec "$bin" >/dev/null 2>&1
    got=$?
    if _e2e_runtime_failure "tool17_target_code_size(default)" "$got"; then return; fi
    if [ "$got" = 42 ]; then echo "ok   tool17_target_code_size: omitted code_size defaults to b64"; else echo "FAIL tool17_target_code_size: default exit=$got want 42"; fail=1; fi
  else
    echo "FAIL tool17_target_code_size: default build rc=$rc diagnostic=$(cat "$T/tool17_target_code_size.default.err" 2>/dev/null)"; fail=1
  fi

  p="$root/b32"
  rm -rf "$p/target"
  ( cd "$p" && "$CC" build package.al ) >/dev/null 2>"$T/tool17_target_code_size.b32.err"
  rc=$?
  bin="$p/target/debug/code-size-b32"
  if [ "$rc" = 0 ] && [ -x "$bin" ]; then
    _e2e_exec "$bin" >/dev/null 2>&1
    got=$?
    if _e2e_runtime_failure "tool17_target_code_size(b32)" "$got"; then return; fi
    if [ "$got" = 42 ]; then echo "ok   tool17_target_code_size: explicit b32 selected"; else echo "FAIL tool17_target_code_size: b32 exit=$got want 42"; fail=1; fi
  else
    echo "FAIL tool17_target_code_size: b32 build rc=$rc diagnostic=$(cat "$T/tool17_target_code_size.b32.err" 2>/dev/null)"; fail=1
  fi
  rm -rf "$root"/*/target
}

## Issue #251 / TOOL-17 + Comptime §7.1/§9 — declaration-level `when` guards must use the same
## selected artifact facts as the lower. The false duplicate declarations also call nonexistent
## functions, so a passing check/build proves they were removed before resolution rather than merely
## tolerated. Keep the package target row-private and inspect the object GAS before assembly.
tool17_declaration_target_when_test() {
  root="$(_fixture_tree package)/when_guard_target_declaration"
  p="$root"
  rm -rf "$p/target"
  ( cd "$p" && "$CC" check package.al ) >/dev/null 2>"$T/tool17_declaration_target_when.check.err"
  rc=$?
  if [ "$rc" = 0 ] && [ ! -e "$p/target" ] && [ ! -s "$T/tool17_declaration_target_when.check.err" ]; then
    echo "ok   tool17_declaration_target_when: check drops inactive declarations"
  else
    echo "FAIL tool17_declaration_target_when: check rc=$rc target=$(test -e "$p/target" && echo yes || echo no) diagnostic=$(cat "$T/tool17_declaration_target_when.check.err" 2>/dev/null)"
    fail=1
  fi

  rm -rf "$p/target"
  ( cd "$p" && "$CC" build package.al ) >/dev/null 2>"$T/tool17_declaration_target_when.build.err"
  rc=$?
  obj="$p/target/debug/when-guard-target-declaration.o"
  gas="$obj.s"
  if [ "$rc" = 0 ] && [ -f "$obj" ] && [ -s "$gas" ] \
    && grep -qF 'movq $20' "$gas" && grep -qF 'movq $22' "$gas" \
    && ! grep -qF 'movq $200' "$gas" && ! grep -qF 'movq $220' "$gas" \
    && ! grep -qF 'missing_kind_branch' "$gas" && ! grep -qF 'missing_size_branch' "$gas" \
    && ! grep -qF 'missing_kind_branch' "$T/tool17_declaration_target_when.build.err" \
    && ! grep -qF 'missing_size_branch' "$T/tool17_declaration_target_when.build.err"; then
    echo "ok   tool17_declaration_target_when: object emits only selected kind/code_size branches"
  else
    echo "FAIL tool17_declaration_target_when: build rc=$rc artifact=$obj diagnostic=$(cat "$T/tool17_declaration_target_when.build.err" 2>/dev/null)"
    fail=1
  fi
  rm -rf "$p/target"
}

## TOOL-17 / Tooling §2.7 — `Package` and `Target` are manifest-only structures, while the selected
## target's published projections remain ordinary prelude data. Negative source modules must be
## rejected identically by `check` and `build`, with no target artifact; the positive package must keep
## `check` semantic-only and preserve its `Kind`/`CodeSize` result at runtime.
tool17_prelude_visibility_test() {
  root="$(_fixture_tree package)/tool17_prelude_visibility"
  for d in negative_package negative_target; do
    p="$root/$d"
    rm -rf "$p/target"
    ( cd "$p" && "$CC" check package.al ) >"$T/tool17_prelude_visibility.$d.check.out" 2>"$T/tool17_prelude_visibility.$d.check.err"
    rc=$?
    if [ "$d" = negative_package ]; then
      needle='manifest-only structure Package cannot be constructed from ordinary source at line 3 in main'
    else
      needle='manifest-only structure Target cannot be constructed from ordinary source at line 3 in main'
    fi
    if [ "$rc" = 1 ] && [ ! -s "$T/tool17_prelude_visibility.$d.check.out" ] \
      && [ ! -e "$p/target" ] && grep -qF "$needle" "$T/tool17_prelude_visibility.$d.check.err"; then
      echo "ok   tool17_prelude_visibility/$d(check): located reject without artifact"
    else
      echo "FAIL tool17_prelude_visibility/$d(check): rc=$rc target=$(test -e "$p/target" && echo yes || echo no) diagnostic=$(cat "$T/tool17_prelude_visibility.$d.check.err" 2>/dev/null)"
      fail=1
    fi

    rm -rf "$p/target"
    ( cd "$p" && "$CC" build package.al ) >"$T/tool17_prelude_visibility.$d.build.out" 2>"$T/tool17_prelude_visibility.$d.build.err"
    rc=$?
    if [ "$rc" = 1 ] && [ ! -e "$p/target" ] \
      && grep -qF "$needle" "$T/tool17_prelude_visibility.$d.build.err"; then
      echo "ok   tool17_prelude_visibility/$d(build): same located reject without artifact"
    else
      echo "FAIL tool17_prelude_visibility/$d(build): rc=$rc target=$(test -e "$p/target" && echo yes || echo no) diagnostic=$(cat "$T/tool17_prelude_visibility.$d.build.err" 2>/dev/null)"
      fail=1
    fi
  done

  p="$root/negative_root"
  rm -rf "$p/target"
  ( cd "$p" && "$CC" check package.al ) >"$T/tool17_prelude_visibility.negative_root.check.out" 2>"$T/tool17_prelude_visibility.negative_root.check.err"
  rc=$?
  needle='manifest-only structure Target cannot be constructed from ordinary source at line 3 in package'
  if [ "$rc" = 1 ] && [ ! -s "$T/tool17_prelude_visibility.negative_root.check.out" ] \
    && [ ! -e "$p/target" ] && grep -qF "$needle" "$T/tool17_prelude_visibility.negative_root.check.err"; then
    echo "ok   tool17_prelude_visibility/negative_root(check): source after manifest is rejected"
  else
    echo "FAIL tool17_prelude_visibility/negative_root(check): rc=$rc target=$(test -e "$p/target" && echo yes || echo no) diagnostic=$(cat "$T/tool17_prelude_visibility.negative_root.check.err" 2>/dev/null)"
    fail=1
  fi

  rm -rf "$p/target"
  ( cd "$p" && "$CC" build package.al ) >"$T/tool17_prelude_visibility.negative_root.build.out" 2>"$T/tool17_prelude_visibility.negative_root.build.err"
  rc=$?
  if [ "$rc" = 1 ] && [ ! -e "$p/target" ] \
    && grep -qF "$needle" "$T/tool17_prelude_visibility.negative_root.build.err"; then
    echo "ok   tool17_prelude_visibility/negative_root(build): same located reject without artifact"
  else
    echo "FAIL tool17_prelude_visibility/negative_root(build): rc=$rc target=$(test -e "$p/target" && echo yes || echo no) diagnostic=$(cat "$T/tool17_prelude_visibility.negative_root.build.err" 2>/dev/null)"
    fail=1
  fi

  p="$root/positive"
  rm -rf "$p/target"
  ( cd "$p" && "$CC" check package.al ) >"$T/tool17_prelude_visibility.positive.check.out" 2>"$T/tool17_prelude_visibility.positive.check.err"
  rc=$?
  if [ "$rc" = 0 ] && [ ! -e "$p/target" ] && [ ! -s "$T/tool17_prelude_visibility.positive.check.err" ]; then
    echo "ok   tool17_prelude_visibility/positive(check): projections accepted without artifact"
  else
    echo "FAIL tool17_prelude_visibility/positive(check): rc=$rc target=$(test -e "$p/target" && echo yes || echo no) diagnostic=$(cat "$T/tool17_prelude_visibility.positive.check.err" 2>/dev/null)"
    fail=1
  fi
  ( cd "$p" && "$CC" build package.al ) >"$T/tool17_prelude_visibility.positive.build.out" 2>"$T/tool17_prelude_visibility.positive.build.err"
  rc=$?
  bin="$p/target/debug/tool17-prelude-positive"
  if [ "$rc" = 0 ] && [ -x "$bin" ]; then
    _e2e_exec "$bin" >/dev/null 2>&1
    got=$?
    if _e2e_runtime_failure "tool17_prelude_visibility/positive(build)" "$got"; then return; fi
    if [ "$got" = 42 ]; then echo "ok   tool17_prelude_visibility/positive(build): projections preserved, artifact 42"; else echo "FAIL tool17_prelude_visibility/positive(build): exit=$got want 42"; fail=1; fi
  else
    echo "FAIL tool17_prelude_visibility/positive(build): rc=$rc artifact=$(test -x "$bin" && echo yes || echo no) diagnostic=$(cat "$T/tool17_prelude_visibility.positive.build.err" 2>/dev/null)"
    fail=1
  fi
  rm -rf "$root"/*/target
}

build_profile_flags_test() {
  # (1) fold bool flags + bare integer value
  pd="$T/e2e_pflags"; rm -rf "$pd"; mkdir -p "$pd/src"
  cat > "$pd/package.al" <<'EOF'
app := Package(version = "0.1.0", source_dir = "src", target_dir = "target",
    profile_flags = [
        FlagDecl(name = "verbose", type = bool, default = true),
        FlagDecl(name = "max_depth", type = u64, default = 7),
    ],
    targets = [
        Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf, entry = "_start", output = "prog"),
    ])
EOF
  cat > "$pd/src/main.al" <<'EOF'
main := fn() -> u64 {
  mut r := 0
  comptime if build.debug { r = r + 1 } else { r = r + 100 }
  comptime if build.verbose { r = r + 2 } else { r = r + 200 }
  d := build.max_depth
  return r + d
}
EOF
  ( cd "$pd" && "$CC" build package.al ) >/dev/null 2>&1 || { echo "FAIL build_profile_flags(fold): build"; fail=1; return; }
  _e2e_exec "$pd/target/debug/prog" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "build_profile_flags(fold)" "$got"; then return; fi
  if [ "$got" = 10 ]; then echo "ok   build_profile_flags(fold): comptime-if bool + bare int value = 10"; else echo "FAIL build_profile_flags(fold): exit=$got want=10"; fail=1; fi
  # (2) default_profile = release folds build.debug FALSE
  pr="$T/e2e_pflags_rel"; rm -rf "$pr"; mkdir -p "$pr/src"
  cat > "$pr/package.al" <<'EOF'
app := Package(version = "0.1.0", source_dir = "src", target_dir = "target",
    default_profile = "release",
    profile_flags = [ FlagDecl(name = "opt", type = bool, default = false) ],
    targets = [ Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf, entry = "_start", output = "prog") ])
EOF
  cat > "$pr/src/main.al" <<'EOF'
main := fn() -> u64 {
  mut r := 0
  comptime if build.debug { r = r + 1 } else { r = r + 40 }
  comptime if build.opt { r = r + 100 } else { r = r + 2 }
  return r
}
EOF
  ( cd "$pr" && "$CC" build package.al ) >/dev/null 2>&1 || { echo "FAIL build_profile_flags(release): build"; fail=1; return; }
  _e2e_exec "$pr/target/release/prog" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "build_profile_flags(release)" "$got"; then return; fi
  if [ "$got" = 42 ]; then echo "ok   build_profile_flags(release): default_profile=release folds build.debug false = 42"; else echo "FAIL build_profile_flags(release): exit=$got want=42"; fail=1; fi
  # (3) explicit profile selection and per-profile override
  po="$T/e2e_pflags_override"; rm -rf "$po"; mkdir -p "$po/src"
  cat > "$po/package.al" <<'EOF'
app := Package(version = "0.1.0", source_dir = "src", target_dir = "target",
    profile_flags = [ FlagDecl(name = "opt", type = bool, default = false) ],
    profiles = [ Profile(name = "release", flags = [ FlagSet(name = "opt", value = true) ]) ],
    targets = [ Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf, entry = "_start", output = "prog") ])
EOF
  cat > "$po/src/main.al" <<'EOF'
main := fn() -> u64 {
  comptime if build.opt { return 42 } else { return 7 }
}
@test("release profile") fn() {
  comptime if build.opt { return } else { panic("test profile was not forwarded") }
}
EOF
  ( cd "$po" && "$CC" build --profile release package.al ) >/dev/null 2>&1 || { echo "FAIL build_profile_flags(override): --profile build"; fail=1; return; }
  _e2e_exec "$po/target/release/prog" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "build_profile_flags(override)" "$got"; then return; fi
  if [ "$got" = 42 ]; then echo "ok   build_profile_flags(override): --profile release applies FlagSet override = 42"; else echo "FAIL build_profile_flags(override): exit=$got want=42"; fail=1; fi
  _e2e_exec_in "$po" "$CC" test --profile release package.al >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "build_profile_flags(test)" "$got"; then return; fi
  if [ "$got" = 0 ]; then echo "ok   build_profile_flags(test): package test receives --profile release"; else echo "FAIL build_profile_flags(test): --profile release exit=$got want=0"; fail=1; fi
  rm -rf "$po/target"
  ( cd "$po" && "$CC" build --release package.al ) >/dev/null 2>&1 || { echo "FAIL build_profile_flags(override): --release build"; fail=1; return; }
  _e2e_exec "$po/target/release/prog" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "build_profile_flags(override-release)" "$got"; then return; fi
  if [ "$got" = 42 ]; then echo "ok   build_profile_flags(override): --release applies release FlagSet = 42"; else echo "FAIL build_profile_flags(override): --release exit=$got want=42"; fail=1; fi
  # (4) undeclared build.<name> fails loud
  pb="$T/e2e_pflags_bad"; rm -rf "$pb"; mkdir -p "$pb/src"
  cat > "$pb/package.al" <<'EOF'
app := Package(version = "0.1.0", source_dir = "src", target_dir = "target",
    targets = [ Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf, entry = "_start", output = "prog") ])
EOF
  printf 'main := fn() -> u64 {\n  comptime if build.nope { return 1 } else { return 2 }\n}\n' > "$pb/src/main.al"
  ( cd "$pb" && "$CC" build package.al ) >/dev/null 2>&1; rc=$?
  if [ "$rc" != 0 ]; then echo "ok   build_profile_flags(reject): undeclared build.<name> fails loud"; else echo "FAIL build_profile_flags(reject): build succeeded, want fail-loud"; fail=1; fi
  # (4b) malformed profile overrides report the manifest line that owns the profile configuration.
  pbc="$(_fixture_tree package)/profile_bad_undeclared"; rm -rf "$pbc/target"
  pbd="$T/e2e_pflags_bad_diag"; rm -f "$pbd"
  ( cd "$pbc" && "$CC" build package.al ) >/dev/null 2>"$pbd"; rc=$?
  if [ "$rc" != 0 ]; then echo "ok   build_profile_flags(reject): undeclared profile override fails loud"; else echo "FAIL build_profile_flags(reject): undeclared profile override succeeded"; fail=1; fi
  if grep -q "config: profile flag override names an undeclared profile_flags entry at line 4 in package.al" "$pbd"; then
    echo "ok   build_profile_flags(reject): profile config diagnostic is located"
  else
    echo "FAIL build_profile_flags(reject): profile config diagnostic is not located"; fail=1
  fi
  rm -f "$pbd"
  # (5) string/enum profile conditions fold in the lowerer (Tooling §2.6/§2.7): `build.<name> == "str"`
  # and `build.<name> == Enum.Variant` compare by str-equality / enum-variant, exactly like arch guards.
  pv="$(_fixture_tree package)/profile_values"; rm -rf "$pv/target"
  ( cd "$pv" && "$CC" build package.al ) >/dev/null 2>&1 || { echo "FAIL build_profile_flags(str/enum): default build"; fail=1; rm -rf "$pv/target"; return; }
  _e2e_exec "$pv/target/debug/profile-values" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "build_profile_flags(str/enum-default)" "$got"; then return; fi
  if [ "$got" = 11 ]; then echo "ok   build_profile_flags(str/enum): default str+enum fold = 11"; else echo "FAIL build_profile_flags(str/enum): default exit=$got want=11"; fail=1; fi
  rm -rf "$pv/target"
  ( cd "$pv" && "$CC" build --profile fast package.al ) >/dev/null 2>&1 || { echo "FAIL build_profile_flags(str/enum): --profile fast build"; fail=1; rm -rf "$pv/target"; return; }
  _e2e_exec "$pv/target/fast/profile-values" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "build_profile_flags(str/enum-fast)" "$got"; then return; fi
  if [ "$got" = 42 ]; then echo "ok   build_profile_flags(str/enum): --profile fast str+enum override = 42"; else echo "FAIL build_profile_flags(str/enum): --profile fast exit=$got want=42"; fail=1; fi
  rm -rf "$pv/target"
  ( cd "$pv" && "$CC" build --release package.al ) >/dev/null 2>&1 || { echo "FAIL build_profile_flags(str/enum): --release build"; fail=1; rm -rf "$pv/target"; return; }
  _e2e_exec "$pv/target/release/profile-values" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "build_profile_flags(str/enum-release)" "$got"; then return; fi
  if [ "$got" = 42 ]; then echo "ok   build_profile_flags(str/enum): --release str+enum override = 42"; else echo "FAIL build_profile_flags(str/enum): --release exit=$got want=42"; fail=1; fi
  rm -rf "$pv/target"
  # (6) integer profile values fold bare literal equality/inequality in comptime conditions.
  pi="$(_fixture_tree package)/profile_int_values"; rm -rf "$pi/target"
  ( cd "$pi" && "$CC" build package.al ) >/dev/null 2>&1 || { echo "FAIL build_profile_flags(int): default build"; fail=1; rm -rf "$pi/target"; return; }
  _e2e_exec "$pi/target/debug/profile-int-values" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "build_profile_flags(int-default)" "$got"; then return; fi
  if [ "$got" = 7 ]; then echo "ok   build_profile_flags(int): default integer comparisons = 7"; else echo "FAIL build_profile_flags(int): default exit=$got want=7"; fail=1; fi
  rm -rf "$pi/target"
  ( cd "$pi" && "$CC" build --profile release package.al ) >/dev/null 2>&1 || { echo "FAIL build_profile_flags(int): --profile release build"; fail=1; rm -rf "$pi/target"; return; }
  _e2e_exec "$pi/target/release/profile-int-values" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "build_profile_flags(int-release)" "$got"; then return; fi
  if [ "$got" = 42 ]; then echo "ok   build_profile_flags(int): --profile release comparisons = 42"; else echo "FAIL build_profile_flags(int): release exit=$got want=42"; fail=1; fi
  rm -rf "$pi/target"
}

# TOOL-5 — native `alatyr test` runs every test in an isolated child process. Void tests pass when
# they return normally, Result::Err contributes one failure, and a trapped test must not prevent a
# later test from running. The final case therefore distinguishes isolation from the old in-process
# runner: the trap would terminate the whole runner with a signal before the following void test.
native_test_runner_test() {
  local report_file state1 state4
  p="$T/e2e_native_test_runner.al"
  cat > "$p" <<'EOF'
@test("void before") fn() {
}
@test("soft failure") fn() -> Result(usize, str) {
  return Result(usize, str).Err("expected")
}
@test("void after soft failure") fn() {
}
EOF
  _e2e_exec "$CC" test -k "$p" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "native_test_runner(result)" "$got"; then return; fi
  if [ "$got" = 1 ]; then echo "ok   native_test_runner(result): void + soft Err = 1"; else echo "FAIL native_test_runner(result): got $got want 1"; fail=1; fi
  report_file="$T/native_test_runner.default.out"
  _e2e_exec_capture_combined "$report_file" "$CC" test "$p"; report_rc=$?
  report="$(<"$report_file")"
  if _e2e_runtime_failure "native_test_runner(report)" "$report_rc"; then return; fi
  if [ "$report_rc" = 1 ] && case "$report" in *"test void before: ok"*) true ;; *) false ;; esac; then
    echo "ok   native_test_runner(report): passing descriptions are reported"
  else
    echo "FAIL native_test_runner(report): missing passing description, rc=$report_rc, output=$report"; fail=1
  fi
  if [ "$report_rc" = 1 ] && case "$report" in *"test soft failure: FAIL (soft)"*) true ;; *) false ;; esac; then
    echo "ok   native_test_runner(report): soft failures identify Result::Err"
  else
    echo "FAIL native_test_runner(report): missing failing description, rc=$report_rc, output=$report"; fail=1
  fi
  if [ "$report_rc" = 1 ] && case "$report" in *"test void after soft failure"*) false ;; *) true ;; esac; then
    echo "ok   native_test_runner(fail-fast): default stops launching after first failure"
  else
    echo "FAIL native_test_runner(fail-fast): default reported a later test, rc=$report_rc, output=$report"; fail=1
  fi
  report_file="$T/native_test_runner.keep_going.out"
  _e2e_exec_capture_combined "$report_file" "$CC" test -k "$p"; report_rc=$?
  report="$(<"$report_file")"
  if _e2e_runtime_failure "native_test_runner(keep-going)" "$report_rc"; then return; fi
  if [ "$report_rc" = 1 ] && case "$report" in *"test void after soft failure: ok"*) true ;; *) false ;; esac; then
    echo "ok   native_test_runner(keep-going): -k reports continue after soft failure"
  else
    echo "FAIL native_test_runner(keep-going): later test report missing, rc=$report_rc, output=$report"; fail=1
  fi
  _e2e_exec "$CC" test "$p" void >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "native_test_runner(filter/void)" "$got"; then return; fi
  if [ "$got" = 0 ]; then echo "ok   native_test_runner(filter): void substring selects passing tests"; else echo "FAIL native_test_runner(filter): got $got want 0"; fail=1; fi
  _e2e_exec "$CC" test "$p" soft >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "native_test_runner(filter/soft)" "$got"; then return; fi
  if [ "$got" = 1 ]; then echo "ok   native_test_runner(filter): soft substring selects failing test"; else echo "FAIL native_test_runner(filter): got $got want 1"; fail=1; fi

  p="$T/e2e_native_test_runner_trap.al"
  cat > "$p" <<'EOF'
@test("trap") fn() {
  panic("expected trap")
}
@test("after trap") fn() {
}
EOF
  _e2e_exec "$CC" test -k "$p" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "native_test_runner(isolation)" "$got"; then return; fi
  if [ "$got" = 1 ]; then echo "ok   native_test_runner(isolation): trap + later void = 1"; else echo "FAIL native_test_runner(isolation): got $got want 1"; fail=1; fi
  report_file="$T/native_test_runner.trap.out"
  _e2e_exec_capture_combined "$report_file" "$CC" test -k "$p"; report_rc=$?
  report="$(<"$report_file")"
  if _e2e_runtime_failure "native_test_runner(trap-report)" "$report_rc"; then return; fi
  if [ "$report_rc" = 1 ] && case "$report" in *"test trap: FAIL (trap)"*) true ;; *) false ;; esac; then
    echo "ok   native_test_runner(report): traps identify abnormal child exits"
  else
    echo "FAIL native_test_runner(report): missing trap detail, rc=$report_rc, output=$report"; fail=1
  fi

  report_file="$T/native_test_runner.invalid_jobs.out"
  _e2e_exec_capture_combined "$report_file" "$CC" test -j0 "$p"; bad_rc=$?
  bad="$(<"$report_file")"
  if _e2e_runtime_failure "native_test_runner(jobs-invalid)" "$bad_rc"; then return; fi
  if [ "$bad_rc" = 40 ] && case "$bad" in *"invalid -j"*"positive integer"*) true ;; *) false ;; esac; then
    echo "ok   native_test_runner(jobs): invalid -j0 diagnosed"
  else
    echo "FAIL native_test_runner(jobs): -j0 rc=$bad_rc output=$bad"; fail=1
  fi

  p="$T/e2e_native_test_runner_jobs.al"
  cat > "$p" <<'EOF'
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
sys_nanosleep := @abi(syscall) fn(num : usize, req : usize, rem : usize) -> isize

@test("sleep one") fn() {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 16, 3, 34, bitcast(usize, neg1), 0)
  base := unchecked bitcast(usize, r)
  secp := unchecked bitcast(ptr(mut usize), base)
  nsecp := unchecked bitcast(ptr(mut usize), base + 8)
  deref(secp) = 1
  deref(nsecp) = 0
  z := unchecked sys_nanosleep(35, base, 0)
}
@test("sleep two") fn() {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 16, 3, 34, bitcast(usize, neg1), 0)
  base := unchecked bitcast(usize, r)
  secp := unchecked bitcast(ptr(mut usize), base)
  nsecp := unchecked bitcast(ptr(mut usize), base + 8)
  deref(secp) = 1
  deref(nsecp) = 0
  z := unchecked sys_nanosleep(35, base, 0)
}
@test("sleep three") fn() {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 16, 3, 34, bitcast(usize, neg1), 0)
  base := unchecked bitcast(usize, r)
  secp := unchecked bitcast(ptr(mut usize), base)
  nsecp := unchecked bitcast(ptr(mut usize), base + 8)
  deref(secp) = 1
  deref(nsecp) = 0
  z := unchecked sys_nanosleep(35, base, 0)
}
@test("sleep four") fn() {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 16, 3, 34, bitcast(usize, neg1), 0)
  base := unchecked bitcast(usize, r)
  secp := unchecked bitcast(ptr(mut usize), base)
  nsecp := unchecked bitcast(ptr(mut usize), base + 8)
  deref(secp) = 1
  deref(nsecp) = 0
  z := unchecked sys_nanosleep(35, base, 0)
}
EOF
  t0=$(date +%s%N); _e2e_exec "$CC" test -j1 "$p" >/dev/null 2>&1; rc1=$?; t1=$(date +%s%N)
  state1="$E2E_RUNTIME_STATE"
  t2=$(date +%s%N); _e2e_exec "$CC" test -j4 "$p" >/dev/null 2>&1; rc4=$?; t3=$(date +%s%N)
  state4="$E2E_RUNTIME_STATE"
  seq_ms=$(( (t1 - t0) / 1000000 ))
  par_ms=$(( (t3 - t2) / 1000000 ))
  if _e2e_runtime_failure "native_test_runner(jobs/-j1)" "$rc1" "$state1"; then return; fi
  if _e2e_runtime_failure "native_test_runner(jobs/-j4)" "$rc4" "$state4"; then return; fi
  if [ "$rc1" = 0 ] && [ "$rc4" = 0 ] && [ "$seq_ms" -ge 3500 ] && [ "$par_ms" -le 2500 ] && [ $((seq_ms - par_ms)) -ge 1200 ]; then
    # The measured durations are deliberately NOT in the success line: this is the only assertion in
    # the suite whose verdict is a timing comparison, and printing the numbers on success made the log
    # differ between two runs of an unchanged tree for no benefit. On FAILURE they are printed (below),
    # which is where they are worth having.
    echo "ok   native_test_runner(jobs): -j4 overlaps sleeping tests (-j1 >= 3500ms, -j4 <= 2500ms, gap >= 1200ms)"
  else
    echo "FAIL native_test_runner(jobs): expected overlap, rc1=$rc1 rc4=$rc4 seq=${seq_ms}ms par=${par_ms}ms"; fail=1
  fi
}

# TOOL-5 contract fixture from the codec integration: both @test roots are linked, including the
# private helper, and each conditional Result.Err remains a soft failure. A missing test root would
# fail at link time; a lost enum discriminant would report success instead of two soft failures.
tool5_contract_test() {
  p="$(_fixture_tree package)/tool5_contract/package.al"
  report_file="$T/tool5_contract.test.out"
  _e2e_exec_capture_combined "$report_file" "$CC" test -k "$p"; got=$?
  report="$(<"$report_file")"
  if _e2e_runtime_failure "tool5_contract(test)" "$got"; then return; fi
  if [ "$got" = 2 ] && case "$report" in *"test conditional Err tag without helper: FAIL (soft)"*) true ;; *) false ;; esac \
      && case "$report" in *"test private helper and conditional Err: FAIL (soft)"*) true ;; *) false ;; esac; then
    echo "ok   tool5_contract: private helper root + two conditional Err soft failures"
  else
    echo "FAIL tool5_contract: rc=$got output=$report"
    fail=1
  fi
}

# name, want-line — the program must be rejected (rc 1) AND its stderr diagnostic must name the
# expected 1-based source line ("... at line N"), proving the failure carries a source location
# (§5). A "location not tracked" message (a poison with no span) fails this.
check_located() {
  src="$E2E_TEST/$1.al"
  [ -f "$src" ] || { echo "MISS $1: no $src"; fail=1; return; }
  msg="$("$CC" check "$src" 2>&1 >/dev/null)"; got=$?
  if [ "$got" != 1 ]; then echo "FAIL $1: check rc=$got want 1"; fail=1; return; fi
  case "$msg" in
    *"at line $2"*) echo "ok   $1: located line $2" ;;
    *) echo "FAIL $1: want 'at line $2', got: $msg"; fail=1 ;;
  esac
}

# name, want-line, message — both public semantic entry points must reject with the same located
# diagnostic. This locks check/build parity for errors that used to surface only as linker failures.
check_build_located() {
  src="$E2E_TEST/$1.al"
  [ -f "$src" ] || { echo "MISS $1: no $src"; fail=1; return; }
  out="$T/e2e_$1.out"
  rm -f "$out"
  cmsg="$("$CC" check "$src" 2>&1 >/dev/null)"; crc=$?
  bmsg="$("$CC" -o "$out" "$src" 2>&1 >/dev/null)"; brc=$?
  if [ "$crc" = 1 ] && case "$cmsg" in *"$3"*"at line $2"*) true ;; *) false ;; esac; then
    echo "ok   $1: check [$3] at line $2"
  else
    echo "FAIL $1: check rc=$crc want [$3] at line $2, got: $cmsg"; fail=1
  fi
  if [ "$brc" = 1 ] && case "$bmsg" in *"$3"*"at line $2"*) true ;; *) false ;; esac; then
    echo "ok   $1: build [$3] at line $2"
  else
    echo "FAIL $1: build rc=$brc want [$3] at line $2, got: $bmsg"; fail=1
  fi
  if [ "$brc" = 1 ] && [ -e "$out" ]; then
    echo "FAIL $1: build rejected but left an output artifact"; fail=1
  fi
}

# name, line, message — an `@limits` contract violation must identify the violated orthogonal limit,
# in both the check and build entry points, rather than being misreported as an unbound name.
check_limit_named() {
  src="$E2E_TEST/$1.al"
  [ -f "$src" ] || { echo "MISS $1: no $src"; fail=1; return; }
  cmsg="$("$CC" check "$src" 2>&1 >/dev/null)"; crc=$?
  bmsg="$("$CC" -o "$T/e2e_$1.limit.out" "$src" 2>&1 >/dev/null)"; brc=$?
  if [ "$crc" = 1 ] && case "$cmsg" in *"$3"*"at line $2"*) true ;; *) false ;; esac; then
    echo "ok   $1: check [$3] at line $2"
  else
    echo "FAIL $1: check rc=$crc want [$3] at line $2, got: $cmsg"; fail=1
  fi
  if [ "$brc" = 1 ] && case "$bmsg" in *"$3"*"at line $2"*) true ;; *) false ;; esac; then
    echo "ok   $1: build [$3] at line $2"
  else
    echo "FAIL $1: build [$3] at line $2, got: $bmsg"; fail=1
  fi
  rm -f "$T/e2e_$1.limit.out"
}

# name, want-line — the program must FAIL TO PARSE (rc 9) AND its stderr diagnostic must be the
# located parse-error message ("alatyr: parse: ... at line N"), proving a parse failure now carries a
# source location, not a bare rc 9 (§5).
check_parse_located() {
  src="$E2E_TEST/$1.al"
  [ -f "$src" ] || { echo "MISS $1: no $src"; fail=1; return; }
  msg="$("$CC" check "$src" 2>&1 >/dev/null)"; got=$?
  if [ "$got" != 9 ]; then echo "FAIL $1: check rc=$got want 9"; fail=1; return; fi
  case "$msg" in
    *"parse"*"at line $2"*) echo "ok   $1: parse located line $2" ;;
    *) echo "FAIL $1: want parse 'at line $2', got: $msg"; fail=1 ;;
  esac
}

# name, want-line, needle — a parse failure (rc 9) whose located diagnostic ALSO names the EXPECTED
# token kind ("(expected …)"), proving the `ParseErr` payload is decoded (§5). The needle is the
# rendered expectation cue.
check_parse_expected() {
  src="$E2E_TEST/$1.al"
  [ -f "$src" ] || { echo "MISS $1: no $src"; fail=1; return; }
  msg="$("$CC" check "$src" 2>&1 >/dev/null)"; got=$?
  if [ "$got" != 9 ]; then echo "FAIL $1: check rc=$got want 9"; fail=1; return; fi
  case "$msg" in
    *"parse"*"$3"*"at line $2"*) echo "ok   $1: parse expected [$3] line $2" ;;
    *) echo "FAIL $1: want parse '$3' 'at line $2', got: $msg"; fail=1 ;;
  esac
}

# A multi-file check whose error is in the SECOND file must report a FILE-RELATIVE line ("at line 3")
# and name the owning module ("in reject_located_multi") — not a line counted across mf_helper.al.
check_located_multi() {
  h="$E2E_TEST/mf_helper.al"; e="$E2E_TEST/reject_located_multi.al"
  [ -f "$h" ] && [ -f "$e" ] || { echo "MISS check_located_multi: sources"; fail=1; return; }
  msg="$("$CC" check "$h" "$e" 2>&1 >/dev/null)"; got=$?
  if [ "$got" != 1 ]; then echo "FAIL check_located_multi: check rc=$got want 1"; fail=1; return; fi
  case "$msg" in
    *"at line 5 in reject_located_multi"*) echo "ok   check_located_multi: located line 5 in module" ;;
    *) echo "FAIL check_located_multi: want 'at line 5 in reject_located_multi', got: $msg"; fail=1 ;;
  esac
}

# limits I9 locality: `@limits(no_comptime)` in file A must NOT restrict file B (which uses comptime,
# no limit). A per-file-scoped check of `A B` ACCEPTS; a (wrong) program-wide check would reject.
limit_scope_multi() {
  a="$E2E_TEST/limit_scope_a.al"; b="$E2E_TEST/limit_scope_b.al"
  [ -f "$a" ] && [ -f "$b" ] || { echo "MISS limit_scope_multi: sources"; fail=1; return; }
  "$CC" check "$a" "$b" >/dev/null 2>&1; got=$?
  if [ "$got" = 0 ]; then echo "ok   limit_scope_multi: per-file (B not restricted by A no_comptime)"; else echo "FAIL limit_scope_multi: check rc=$got want 0"; fail=1; fi
}

## Moved up from the fixture table: a helper must be defined ABOVE the driver's arming point
## or its rows cannot be scheduled (see `_e2e_check_armed`). Its CALL SITE did not move.
check_ra_const_fold() {
  src="$E2E_TEST/ra_const_fold.al"
  asm="$T/e2e_ra_const_fold.s"
  out="$T/e2e_ra_const_fold.out"
  fallback="$T/e2e_ra_const_fold_fallback.out"
  "$CC" "$src" > "$asm" 2>/dev/null || { echo "FAIL ra_const_fold: emit"; fail=1; return; }
  if grep -Eq '^[[:space:]]*(andq|orq|xorq) ' "$asm"; then
    echo "FAIL ra_const_fold: immediate bitwise op survived scalar-IR folding"; fail=1; return
  fi
  "$CC" -o "$out" "$src" >/dev/null 2>&1 || { echo "FAIL ra_const_fold: build"; fail=1; return; }
  _e2e_exec "$out" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "ra_const_fold" "$got"; then return; fi
  if [ "$got" != 42 ]; then echo "FAIL ra_const_fold: got $got want 42"; fail=1; return; fi
  ALATYR_RA=0 "$CC" -o "$fallback" "$src" >/dev/null 2>&1 || { echo "FAIL ra_const_fold: fallback build"; fail=1; return; }
  _e2e_exec "$fallback" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "ra_const_fold(fallback)" "$got"; then return; fi
  if [ "$got" = 42 ]; then echo "ok   ra_const_fold: folded GAS + fallback 42"; else echo "FAIL ra_const_fold: fallback got $got want 42"; fail=1; fi
}

## Moved up from the fixture table: a helper must be defined ABOVE the driver's arming point
## or its rows cannot be scheduled (see `_e2e_check_armed`). Its CALL SITE did not move.
check_ra_arith_const_fold() {
  src="$E2E_TEST/ra_arith_const_fold.al"
  asm="$T/e2e_ra_arith_const_fold.s"
  out="$T/e2e_ra_arith_const_fold.out"
  fallback="$T/e2e_ra_arith_const_fold_fallback.out"
  "$CC" "$src" > "$asm" 2>/dev/null || { echo "FAIL ra_arith_const_fold: emit"; fail=1; return; }
  if grep -Eq '^[[:space:]]*(addq|subq) \$2,|^[[:space:]]*imulq \$7,' "$asm"; then
    echo "FAIL ra_arith_const_fold: unchecked immediate arithmetic survived scalar-IR folding"; fail=1; return
  fi
  "$CC" -o "$out" "$src" >/dev/null 2>&1 || { echo "FAIL ra_arith_const_fold: build"; fail=1; return; }
  _e2e_exec "$out" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "ra_arith_const_fold" "$got"; then return; fi
  if [ "$got" != 42 ]; then echo "FAIL ra_arith_const_fold: got $got want 42"; fail=1; return; fi
  ALATYR_RA=0 "$CC" -o "$fallback" "$src" >/dev/null 2>&1 || { echo "FAIL ra_arith_const_fold: fallback build"; fail=1; return; }
  _e2e_exec "$fallback" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "ra_arith_const_fold(fallback)" "$got"; then return; fi
  if [ "$got" = 42 ]; then echo "ok   ra_arith_const_fold: add/sub/imul GAS fold + fallback 42"; else echo "FAIL ra_arith_const_fold: fallback got $got want 42"; fail=1; fi
}

## Moved up from the fixture table: a helper must be defined ABOVE the driver's arming point
## or its rows cannot be scheduled (see `_e2e_check_armed`). Its CALL SITE did not move.
check_ra_shift_const_fold() {
  src="$E2E_TEST/ra_shift_const_fold.al"
  asm="$T/e2e_ra_shift_const_fold.s"
  out="$T/e2e_ra_shift_const_fold.out"
  fallback="$T/e2e_ra_shift_const_fold_fallback.out"
  "$CC" "$src" > "$asm" 2>/dev/null || { echo "FAIL ra_shift_const_fold: emit"; fail=1; return; }
  if grep -Eq '^[[:space:]]*(shlq|shrq) ' "$asm"; then
    echo "FAIL ra_shift_const_fold: unchecked immediate shift survived scalar-IR folding"; fail=1; return
  fi
  "$CC" -o "$out" "$src" >/dev/null 2>&1 || { echo "FAIL ra_shift_const_fold: build"; fail=1; return; }
  _e2e_exec "$out" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "ra_shift_const_fold" "$got"; then return; fi
  if [ "$got" != 42 ]; then echo "FAIL ra_shift_const_fold: got $got want 42"; fail=1; return; fi
  ALATYR_RA=0 "$CC" -o "$fallback" "$src" >/dev/null 2>&1 || { echo "FAIL ra_shift_const_fold: fallback build"; fail=1; return; }
  _e2e_exec "$fallback" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "ra_shift_const_fold(fallback)" "$got"; then return; fi
  if [ "$got" = 42 ]; then echo "ok   ra_shift_const_fold: logical shift GAS fold + fallback 42"; else echo "FAIL ra_shift_const_fold: fallback got $got want 42"; fail=1; fi
}

## Moved up from the fixture table: a helper must be defined ABOVE the driver's arming point
## or its rows cannot be scheduled (see `_e2e_check_armed`). Its CALL SITE did not move.
check_ra_imm64_widen() {
  src="$E2E_TEST/ra_imm64_widen.al"
  asm="$T/e2e_ra_imm64_widen.s"
  out="$T/e2e_ra_imm64_widen.out"
  fallback="$T/e2e_ra_imm64_widen_fallback.out"
  "$CC" "$src" > "$asm" 2>/dev/null || { echo "FAIL ra_imm64_widen: emit"; fail=1; return; }
  if grep -Eq '^[[:space:]]*(addq|subq|imulq|andq|orq|xorq|cmpq) \$(4294967296|4294967295|2147483648),' "$asm"; then
    echo "FAIL ra_imm64_widen: an out-of-imm32 literal stayed folded into an ALU/compare operand"; fail=1; return
  fi
  if ! grep -Eq '^[[:space:]]*addq \$2147483647,' "$asm"; then
    echo "FAIL ra_imm64_widen: the in-range boundary literal 2^31-1 was needlessly widened"; fail=1; return
  fi
  if ! grep -Eq '^[[:space:]]*andq \$-1,' "$asm"; then
    echo "FAIL ra_imm64_widen: a u64::MAX mask (sign-extends from imm32) was needlessly widened"; fail=1; return
  fi
  "$CC" -o "$out" "$src" >/dev/null 2>&1 || { echo "FAIL ra_imm64_widen: build (as rejected the text)"; fail=1; return; }
  _e2e_exec "$out" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "ra_imm64_widen" "$got"; then return; fi
  if [ "$got" != 42 ]; then echo "FAIL ra_imm64_widen: got $got want 42"; fail=1; return; fi
  _e2e_exec "$CC" run "$src" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "ra_imm64_widen(run)" "$got"; then return; fi
  if [ "$got" != 42 ]; then echo "FAIL ra_imm64_widen: alatyr run got $got want 42"; fail=1; return; fi
  ALATYR_RA=0 "$CC" -o "$fallback" "$src" >/dev/null 2>&1 || { echo "FAIL ra_imm64_widen: fallback build"; fail=1; return; }
  _e2e_exec "$fallback" >/dev/null 2>&1; got=$?
  if _e2e_runtime_failure "ra_imm64_widen(fallback)" "$got"; then return; fi
  if [ "$got" = 42 ]; then echo "ok   ra_imm64_widen: widened GAS assembles, run == build, fallback 42"; else echo "FAIL ra_imm64_widen: fallback got $got want 42"; fail=1; fi
}

# An external test SCRIPT that belongs to this suite (`scripts/<name>.sh`, driven with `ALATYR=$CC`).
# These were four inline `if … fi` blocks; as a helper they become ordinary ROWS, which is what lets
# them be SCHEDULED — `ext_test env_size_test` is the single most expensive row in the gate (measured
# 83 s: 8 serial in-place self-builds inside scripts/env_size_test.sh, ~10.2 s each), so leaving it
# unschedulable set the floor for the whole suite. Its whole-script duration is intentionally not
# passed through the per-target runtime deadline below.
# The script's own output is replayed VERBATIM either way: its `ok …`/`FAIL …` lines are assertions in
# their own right and belong in this log. The old blocks discarded nothing on success but collapsed a
# failure to the single word `FAIL <name>`, which is how "FAIL env_size_test" became the entire public
# record of a failure whose cause was several lines further down.
ext_test() { # name
  script="$ROOT/scripts/$1.sh"
  [ -f "$script" ] || { echo "MISS $1(ext): no $script"; fail=1; return; }
  log="$T/ext_$1.log"
  ALATYR="$CC" bash "$script" > "$log" 2>&1 < /dev/null
  got=$?
  cat "$log"
  if [ "$got" = 0 ]; then echo "ok   $1(ext): exit 0"; else echo "FAIL $1(ext): exit $got"; fail=1; fi
}

## Issue #297 / Comptime §§8.2–9.1 + Tooling §5 — the lower's unsupported comptime-if fold must
## retain the condition's source location after the driver concatenates several files. The helper
## generates a private package so it exercises the file-backed `compile_files_mode` without adding
## corpus rows; the reject is in the first user module and has leading lines so a global-buffer line
## count would be observably wrong. The needle is kept here, not in the generated source, so an old
## compiler cannot pass by echoing its own assertion text. The enum-valued binding is intentionally
## outside issue #268's bounded scalar fold; keep the `unchecked` wrapper so this remains the wrapped
## source-location regression rather than weakening the new scalar path.
issue297_codegen_multi_reject_test() {
  local d="$T/issue297_codegen_multi"
  rm -rf "$d"
  mkdir -p "$d/src" || { echo "FAIL issue297_codegen_multi: scratch"; fail=1; return; }
  printf '%s\n' \
    'app := Package(' \
    '  version = "0.1.0",' \
    '  source_dir = "src",' \
    '  target_dir = "target",' \
    '  targets = [' \
    '    Target(' \
    '      arch = Arch.x86_64,' \
    '      os = Os.linux,' \
    '      env = Env.gnu,' \
    '      container = Container.elf,' \
    '      entry = "_start",' \
    '      output = "issue297-codegen",' \
    '    ),' \
    '  ],' \
    ')' > "$d/package.al"
  printf '%s\n' \
    '## Leading lines make a shared-buffer line count observably wrong.' \
    'E := enum { Zero, One }' \
    '' \
    '' \
    'pub reject_here := fn() -> u64 {' \
    '  mut x : u64 = 5' \
    '  comptime v : E = E.One' \
    '  comptime if unchecked (v == E.One) { x = 30 } else { x = 70 }' \
    '  return x' \
    '}' > "$d/src/helper.al"
  printf '%s\n' \
    'main := fn() -> u64 {' \
    '  return helper::reject_here()' \
    '}' > "$d/src/main.al"

  local needle='codegen: `comptime if` — cannot fold this comptime condition. The lower folds target machine projections, verify.checked, build.<flag>, a module const, an integer comparison, size(T), typeinfo(T).fields/variants.len, a type equality, a `match typeinfo(T)` kind test, resolves(…)/compiles(…), and and/or/not over those. Rejected rather than silently emitting NEITHER branch. at line 8 in helper'
  local err="$T/issue297_codegen_multi.err"
  rm -rf "$d/target"
  ( cd "$d" && "$CC" build package.al > /dev/null 2> "$err" )
  local rc=$?
  local out="$d/target/debug/issue297-codegen"
  if [ "$rc" = 0 ] || [ -e "$out" ] || ! grep -qF "$needle" "$err"; then
    echo "FAIL issue297_codegen_multi: rc=$rc/artifact=$(test -e "$out" && echo yes || echo no)/diagnostic=$(<"$err")"
    fail=1
  else
    echo "ok   issue297_codegen_multi: build rejected with exact located diagnostic in helper"
  fi
}

# ==================================================================================================
# THE DRIVER, part 1 — arm the helpers, then let the table RECORD itself.
#
# Everything from here to the fixture table is machinery; the table itself is untouched data.
# ==================================================================================================

E2E_PHASE=record
E2E_N=0
declare -a E2E_ROW=()

## The single indirection every armed helper goes through. In `record` it appends the row's own
## command line to `E2E_ROW` (`printf %q`, so an argument like `'(export "x"'` survives the round
## trip). In `run` it calls the CLONE, which is why a helper that calls another helper still works.
_dispatch() {
  local kind="$1"; shift
  if [ "$E2E_PHASE" = record ]; then
    E2E_N=$((E2E_N+1))
    printf -v "E2E_ROW[$E2E_N]" '%q ' "$kind" "$@"
  else
    "t_$kind" "$@"
  fi
}

## Clone every helper `f` to `t_f` and replace `f` with a recording stub. `declare -f` is bash's own
## serialisation of a function — re-`eval`ing it is exactly what `export -f` does — so the clone is
## not a textual approximation of the helper, it IS the helper.
## Issue #324 / Types §6.4 + I11 — direct nested fixed-array parameters are fenced before their
## parser-corrupted ABI can reach any backend. Generate these private cases so the refusal matrix does
## not add oracle rows; every negative case is read-only, while the separate one-dimensional control
## proves ordinary array-parameter addressing remains supported on the existing x86 surface.
issue324_nested_array_param_test() {
  local d="$T/issue324_nested_array_param"
  mkdir -p "$d"
  local E2E_TEST="$d"

  write_case() { # name, element type, inner length, outer length, literal, expected element
    local name="$1" typ="$2" inner="$3" outer="$4" values="$5" expected="$6"
    printf '%s\n' \
      '## This read-only case keeps every stored element distinct.' \
      '## The caller supplies both indexes so the old accepted shape has a concrete wrong-value witness.' \
      "read2 := fn(xs : [[$typ; $inner]; $outer], i : u64, j : u64) -> u64 {" \
      '  return u64(xs[i][j])' \
      '}' \
      '' \
      'main := fn() -> u64 {' \
      "  if read2($values, 1, 0) != $expected { return 1 }" \
      '  42' \
      '}' > "$d/$name.al"
  }

  write_case issue324_nested_u8 u8 2 2 '[[11, 12], [21, 22]]' 21
  write_case issue324_nested_u16 u16 2 2 '[[11, 12], [21, 22]]' 21
  write_case issue324_nested_u64 u64 2 2 '[[11, 12], [21, 22]]' 21
  write_case issue324_nested_nonsquare u16 3 2 '[[11, 12, 13], [21, 22, 23]]' 21
  for name in issue324_nested_u8 issue324_nested_u16 issue324_nested_u64 issue324_nested_nonsquare; do
    check_build_located "$name" 3 "nested fixed-array parameter"
    emit_reject_has wat "$name" "nested fixed-array parameter"
    emit_reject_has aarch64 "$name" "nested fixed-array parameter"
    emit_reject_has riscv64 "$name" "nested fixed-array parameter"
  done

  printf '%s\n' \
    '## A one-dimensional array parameter remains a supported control.' \
    'read1 := fn(xs : [u64; 3], i : u64) -> u64 {' \
    '  return xs[i]' \
    '}' \
    '' \
    'main := fn() -> u64 {' \
    '  if read1([11, 22, 42], 2) != 42 { return 1 }' \
    '  42' \
    '}' > "$d/issue324_array_1d_control.al"
  ## The one-dimensional fixed-array parameter control is an x86 control, matching the existing
  ## fixed_array_byte_param row; non-x86 parameter ABI support is a separate pre-existing boundary.
  run_x86 issue324_array_1d_control 42
}

_e2e_arm() {
  local f body n=0
  while read -r _ _ f; do
    case "$f" in _*|t_*) continue ;; esac
    body="$(declare -f "$f")"; body="${body#"$f"}"
    eval "t_$f$body"                     || { echo "FAIL: could not clone helper '$f'"; exit 1; }
    eval "$f() { _dispatch $f \"\$@\"; }" || { echo "FAIL: could not arm helper '$f'"; exit 1; }
    n=$((n+1))
  done < <(declare -F)
  E2E_KINDS="$n"
}

## A helper defined BELOW this point is invisible to the driver: its rows would execute inline during
## the table scan instead of being scheduled, so they would run serially, print out of order, and be
## absent from the row count. That is a silent coverage change, so it is a hard failure with an
## explanation. (This is exactly what four `check_ra_*` helpers used to do — their definitions sat in
## the middle of the table; the definitions moved up here, their call sites did not move at all.)
_e2e_check_armed() {
  local f miss=""
  while read -r _ _ f; do
    case "$f" in _*|t_*) continue ;; esac
    declare -F "t_$f" >/dev/null 2>&1 || miss="$miss $f"
  done < <(declare -F)
  [ -z "$miss" ] && return 0
  echo "FAIL: helper(s) defined below the driver's arming point:$miss"
  echo "     A helper must be defined in the HELPERS region, above \`_e2e_arm\`. Move the definition"
  echo "     up; its call sites in the fixture table can stay exactly where they are."
  return 1
}

_e2e_arm

# ==================================================================================================
# THE FIXTURE TABLE — one row per assertion. Append rows here; nothing below needs to change.
# ==================================================================================================
run smoke 42
## Grammar §2.5: `#` (single-hash) is a line comment, `##` a doc-comment. The self-host
## lexer must skip BOTH — a lone `#` must not fall through as an unrecognized token.
run single_hash_comment 44
run module_const 42
run module_str_const 42
run module_struct_const 42
run module_struct_copy 42
## TYP-8 — struct construction is BY NAME, not by source position. `P(y = 6, x = 5)` used to
## drop the field names and store positionally (y=6 landed in x) — a silent miscompile for any
## out-of-declaration-order literal. The parser now reorders each named field to its declaration
## index (a parse desugar), so it is correct on EVERY backend (`run`, not `run_x86` — verified by
## the arch sweeps). Also exercises a full 3-way permutation + trailing partial init reject at compile.
run struct_field_by_name 42
## TYP-8 check/build parity: check must use the same PASS-1 struct field table as build for
## mixed-type by-name literals, and must reject an unknown named field instead of checking positionally.
run check_struct_field_order 42
## TYP-8 / spec Types §9.4 — STRUCT-FIELD DEFAULTS `x : T = <expr>`: an omitted field with a default is
## FILLED with the default value at ANY position (source-scanned at the decl, re-lexed at the site); a
## provided field OVERRIDES its default; the by-name reorder stays correct with defaults present. A parse
## desugar → correct on every backend (`run`, verified by the arch sweeps).
run struct_field_default 42
## Types §6.5 — ZERO-SIZED TYPES (empty `struct {}`, `[T; 0]`: size 0, align 1, a ZST field shifts
## nothing) + the ZERO-NAMED-FIELD constructor `T()` (grammar §130 empty struct-ctor; §9.4 all-defaulted
## construction). Recognized as construction, not a call, via the by-name struct field-order table.
run zst_and_empty_ctor 42
## TYP-8 / §9.4 — a non-trailing field with NO default and NO provider is a GAP → build FAILS LOUD (a
## defaulted field after it forces the gap to be materialized; a silent wrong binary is forbidden).
build_reject_has reject_struct_gap_no_default "struct construction leaves a non-trailing field unwritten"
## The backstop: a call returning `ptr(<its own type parameter>)` whose type argument the call does not
## name at that position is a located reject, not a silently empty view.
build_reject_has reject_deref_call_pointee "pointee cannot be resolved"
## Types §7 / I11: a live `str`/view expression that has no materialization path must reject rather
## than fall through to the empty `{ptr,len}` pair. The dead `Num(-1)` return sentinel remains exempt.
build_reject_has str_pair_call_field "live str/view expression has no lowering path"
## §8 @packed byte-precise struct layout: sized loads/stores at byte offsets — x86_64-only emit
## (other backends keep the word-sized model), so run_x86 (excluded from the arch sweeps' `^run ` grep).
run_x86 packed_struct 42
## §8 @offset(N) explicit field byte offset (MMIO / register maps): a @packed struct with an overlapping
## @offset field; x86_64-only sized loads/stores at byte offsets, so run_x86 (sweep-excluded).
run_x86 offset_struct 42
## §8 @align(N) raise-alignment lever: a @packed struct with an @align(4) field; the cursor rounds up
## before the field and the struct size rounds to the max field alignment; x86_64-only, so run_x86.
run_x86 align_struct 42
## §8 STRUCT-LEVEL @align(N) struct: raises the whole struct's alignment above natural and rounds its
## size up to that alignment (align(V)=16, size(V)=32 for a 3-word struct); x86_64-only, so run_x86.
run_x86 align_struct_level 42
run_x86 embed_byte_storage 42
## §8 @packed/@offset with a NON-scalar field (str / nested struct / fixed array), 8-aligned, and a scalar
## field read PAST it by value: the aggregate advances the byte cursor by its FULL size and is stored via
## the word-model emitters at a byte->slot-translated position; x86_64-only, so run_x86 (sweep-excluded).
run_x86 packed_str_field 42
run_x86 packed_nested_struct 42
## CLAYOUT: a @packed root containing a @packed nested child must compose both byte cursors;
## the child’s sub-word scalar fields are not at the old word-model offsets.
run_x86 packed_nested_packed_read 42
run_x86 packed_array_field 42
run_x86 packed_byte_array_field 42
## BYTES: ordinary standard-layout structs with direct byte-array fields use exact byte offsets
## for construction, copy, indexed read/write, address-of, by-ref aggregate passing, size and align.
run_x86 standard_byte_array_field 42
## CLAYOUT S4: flat narrow-scalar structs use the Types §6.1 byte layout — natural field alignment,
## declaration order, and tail padding. The mixed u8/u64 row is a word-layout control whose values
## already coincide with the standard result; the all-narrow rows are the selected switch surface.
run clayout_scalar_fields 42
## CLAYOUT S3(d): the same byte offset must survive a pointer-derived struct root. The non-x86
## emitters keep their existing fail-loud pointer-to-aggregate boundary, so this focused x86 row does
## not widen their claimed surface.
run_x86 deref_ptr_standard_byte_array_field 42
## CLAYOUT S3(e): a standard byte-tier struct crosses an ordinary by-value parameter and return;
## all four emitters must load its byte fields through the parameter's caller-owned address.
run standard_byte_abi 42
## #169: the first two narrow fields share one eightbyte; the non-x86 backends must not return 70.
run issue169_standard_byte_return 75
## #169: second-field-only by-value parameter probe; a first-field-only result is insufficient.
run issue169_standard_byte_param 5
## #169 control: pair return → pair parameter preserves both fields; a wider mixed struct stays word-tier.
run issue169_native_byte_abi_control 42
## #169 negative control: a wider byte-layout struct remains fail-loud outside the bounded slice.
run issue169_native_byte_abi_unsupported 42
## #169: the WASM whole-element write must not retain its old partial word copy.
run issue169_wasm_array_write 42
## #169: the WASM nested standard-byte return must not regress from its former trap to a wrong value.
run issue169_wasm_nested_return 23
## BYTES: a direct byte-array component in a typed tuple local uses standard byte offsets.
run_x86 standard_tuple_byte_component 42
build_reject_has reject_standard_tuple_byte_param "a standard-layout byte tuple parameter is not supported yet"
build_reject_has reject_standard_tuple_byte_return "a standard-layout byte tuple return is not supported yet"
build_reject_has reject_standard_tuple_byte_global "a standard-layout byte tuple global is not supported yet"
check_reject_has reject_standard_tuple_byte_global "a standard-layout byte tuple global is not supported yet"
emit_reject_has wat reject_standard_tuple_byte_global "a standard-layout byte tuple global is not supported yet"
emit_reject_has aarch64 reject_standard_tuple_byte_global "a standard-layout byte tuple global is not supported yet"
emit_reject_has riscv64 reject_standard_tuple_byte_global "a standard-layout byte tuple global is not supported yet"
## §8 DIRECT aggregate-field READ from a @packed struct: r.inner.x (nested-struct sub-field) + r.name.len
## (str field), read through the packed byte layout at the aggregate's 8-aligned byte->slot position;
## x86_64-only, so run_x86 (sweep-excluded).
run_x86 packed_agg_read 42
## §8 pointer-to-@packed (ek 7 MMIO map): a `ptr(PackedStruct)` reads a field at its PACKED byte offset
## THROUGH the pointer (sized load at %rax+byte-offset), not the word offset; `deref(p).f` + bare `p.f`;
## x86_64-only byte-precise load, so run_x86 (sweep-excluded).
run_x86 packed_ptr_read 42
## P0 / Memory §§1.6, 4.3, 4.6: a standard-layout nested field through an inline pointer bitcast
## must accumulate byte offsets (inner at 8 + b at 2 = 10), not the old word-tier displacement.
run_x86 nested_deref_bitcast_field 42
## §8 FURTHER-NESTED aggregate sub-field read from a @packed struct (`r.mid.inner.c`, 2 levels deep)
## + a whole aggregate field passed BY-REFERENCE to a fn (`sumit(r.mid.inner)`); the aggregate sits at
## an 8-aligned byte offset and the chain resolves through the word-model slot layout; x86_64-only.
run_x86 packed_agg_nested_read 42
## §8 SUB-8 @packed local COPY: a packed struct of size 5 (NOT a multiple of 8) copied by value to
## another local, with a u64 sentinel neighbour; a frame local is word-padded (ceil(5/8)=1 word) so the
## whole-word copy stays in-slot and never clobbers the neighbour (fields round-trip, sentinel intact);
## x86_64-only byte-precise layout, so run_x86 (sweep-excluded).
run_x86 packed_subword 42
## Issue #163: one focused matrix keeps the canonical scalar-width decision visible to the runtime
## pointer-preservation path and the packed-layout path; the paired fmt row checks round-trip fidelity.
run scalar_width_matrix 42
fmt_test scalar_width_matrix 42
## §8 @packed struct passed BY VALUE as a PARAMETER: an aggregate arg travels by REFERENCE, so the
## callee's slot is `is_ref` and failed the packed-LOCAL gate — every field fell to the word-sized
## `movq 8*index(%rax)` read of a BYTE-precise block (p.b/p.c read 0, p.a read all fields OR-ed into
## one word) while the SAME read on the caller's local was right. x86_64-only byte-precise loads, so
## run_x86 (sweep-excluded). Covers a second hop (a by-ref param re-passed) + the `q := p` copy.
run_x86 packed_param_read 42
## §8 @packed field WRITE through an `in out` PARAMETER — the store dual: a word-sized store missed the
## field AND smeared 8 bytes over its neighbours, visible to the caller. u64 sentinels either side prove
## the store is byte-sized. x86_64-only, so run_x86.
run_x86 packed_param_write 42
## §8 @offset(N) / @align(N) / @endian(big) fields read off a BY-VALUE PARAM — the attribute-lever dual
## of packed_param_read (all three extend the @packed byte layout and were silently wrong the same way:
## the overlap, the cursor rounding and the load-side byte-swap all vanished). x86_64-only, so run_x86.
run_x86 packed_attr_param 42
## §8 @packed struct RETURNED BY VALUE (DEFERRED): the return registers are word-model (one whole
## register per field) while the value is byte-precise, and the return path applies NO packed semantics —
## `r := mk(); r.b` read 0, a PARTIAL packed literal left garbage over the @offset overlays, @endian(big)
## never swapped. `mk().b` only "worked" because the return AND the direct register read were both
## word-model. Rejected at the decl so no caller shape can observe a wrong value.
build_reject_has packed_ret_value "a @packed/@offset/@align/@endian struct returned BY VALUE from a function is not yet supported"
## §8 a @packed struct as a FIELD of a NON-packed struct (DEFERRED): the outer struct lays out word-wise
## while the nested literal stores the inner value byte-precise, so write and read disagree (g.p.b read 0,
## g.p.a read all three packed fields OR-ed into one word). The MIRROR direction — a plain struct nested
## INSIDE a @packed struct — is supported (packed_agg_read / packed_nested_struct) and is unaffected.
build_reject_has packed_in_plain_struct "a @packed/@offset/@align/@endian struct used as a FIELD of a NON-packed struct is not yet supported"
## §8 ARRAY-OF-@packed (DEFERRED): the initialized local array literal must be rejected in sema before
## any backend can apply a word-granular stride to a byte-precise element. Keep the same diagnostic
## needle across check/build/WAT/AArch64/RISC-V; the uninitialized and slice cases below retain their
## separate late lower fences.
check_reject_has packed_array "initialized local array literal whose element is a @packed struct"
build_reject_has packed_array "initialized local array literal whose element is a @packed struct"
## Control: an ordinary array literal remains accepted; its tuple element is not a @packed struct.
check_accept array_of_tuples
build_reject_has reject_p0_packed_array_uninit "an array whose element is a @packed struct is not supported"
## The same ARRAY-OF-@packed fence must hold on every emit-to-stdout backend. These surfaces run their
## front-end check first, then the shared lower_layout query must reject before any GAS/WAT reaches stdout.
emit_reject_has wat packed_array "initialized local array literal whose element is a @packed struct"
emit_reject_has aarch64 packed_array "initialized local array literal whose element is a @packed struct"
emit_reject_has riscv64 packed_array "initialized local array literal whose element is a @packed struct"
emit_reject_has wat reject_p0_packed_array_uninit "an array whose element is a @packed struct is not supported"
emit_reject_has aarch64 reject_p0_packed_array_uninit "an array whose element is a @packed struct is not supported"
emit_reject_has riscv64 reject_p0_packed_array_uninit "an array whose element is a @packed struct is not supported"
build_reject_has reject_p0_packed_slice_param "whose element is a @packed struct is not supported"
emit_reject_has wat reject_p0_packed_slice_param "whose element is a @packed struct is not supported"
emit_reject_has aarch64 reject_p0_packed_slice_param "whose element is a @packed struct is not supported"
emit_reject_has riscv64 reject_p0_packed_slice_param "whose element is a @packed struct is not supported"
## `embed(comptime path : str)` — the reproducible comptime file-embed builtin (Comptime §2.4): bakes
## a file's exact bytes into the program as a read-only `[u8]` sequence. `embed_bytes` embeds the
## 4-byte BINARY fixture (NUL / 0xFF / 'A' / newline) and checks `.len`, each byte, and their sum →
## 42 (byte-exact + binary-safe). `embed_missing` embeds a nonexistent path → the build FAILS LOUD.
run_x86 embed_bytes 42
run_x86 embed_typed_bytes 42
build_reject_has embed_missing "embed cannot open file"
## WHOLE-VALUE assignment of a NON-LITERAL aggregate (a fn return) to a mutable STRUCT global: the
## register/sret return-materialization the local Assign path uses is not modelled for a `.data`
## destination, so a scalar store would silently drop words — the lower FAILS LOUD instead. (`G = S(…)`
## with a struct LITERAL is fully supported — see global_agg_struct_whole_assign.)
build_reject_has reject_global_struct_nonlit_assign "whole-value assignment of a NON-LITERAL aggregate"
check_reject reject_global_struct_nonlit_assign
emit_reject_has wat reject_global_struct_nonlit_assign "whole-value assignment of a NON-LITERAL aggregate"
emit_reject_has aarch64 reject_global_struct_nonlit_assign "whole-value assignment of a NON-LITERAL aggregate"
emit_reject_has riscv64 reject_global_struct_nonlit_assign "whole-value assignment of a NON-LITERAL aggregate"
check_reject reject_global_struct_call_init_nonlit_assign
emit_reject_has wat reject_global_struct_call_init_nonlit_assign "whole-value assignment of a NON-LITERAL aggregate"
emit_reject_has aarch64 reject_global_struct_call_init_nonlit_assign "whole-value assignment of a NON-LITERAL aggregate"
emit_reject_has riscv64 reject_global_struct_call_init_nonlit_assign "whole-value assignment of a NON-LITERAL aggregate"
## WHOLE-STRUCT store through a pointer from an if/match BRANCH (`deref(p) = if … { Rec(…) } …`) into a
## MULTI-WORD pointee: a branch value is not a struct-lit / var / pointee-deref (the multi-word source
## paths), so it fell to the scalar store path and dropped words — the lower FAILS LOUD. (Bind the branch
## to a local first, then `deref(p) = t`.)
build_reject_has deref_store_branch_reject "whole-STRUCT store through a pointer"
## DEEP-CHAIN (`o.mid.inner = v`, `FieldPathAssign`) multi-word FINAL-field whole-assign. A struct
## literal / if-match value is delivered whole (deep_field_agg_write / deep_field_agg_if); these three
## sources FAIL LOUD rather than a silent word-0-only store: a struct VAR (a per-word copy loop is
## mis-lowered to a single word inside the shared helper) and a str/enum final field (unsupported
## END-TO-END — even the nested READ is not lowered).
build_reject_has deep_field_agg_var_reject "multi-word struct VAR into a struct field"
build_reject_has deep_field_agg_str_reject "deep-chain str/enum FINAL field whole-assign"
build_reject_has deep_field_agg_enum_reject "deep-chain str/enum FINAL field whole-assign"
## Hunk C: `.unwrap()`/`.expect()` on a generic `Option(V)` with a MULTI-WORD aggregate payload now WORKS
## (the UFCS instance is re-tagged by the CONCRETE payload type at pre-pass + emit, so it shares the same
## `unwrap__Rec` instance the prefix `unwrap(Rec, o)` produces). Scalar / 1-word keeps working (ufcs_option_expect).
run unwrap_struct_payload 42
run unwrap_ufcs_struct 42
## A bare comparison (`==`/`!=`/`<`/…) over TWO multi-word by-value struct/enum values now routes to the
## structural `base::derive::eq`/`lt` (was a word-0-only silent miscompile: `P(5,7) == P(5,9)` wrongly
## equal). reject_agg_compare locks the classic word-1 case; agg_eq covers `==`/`!=`/`<`/`>` + nested.
run reject_agg_compare 42
run agg_eq 42
## WHOLE-VALUE assignment to a mutable bare-STR global (`S = "…"`): the bare str-global READ path is
## itself broken (`.len` reads 0), so no correct observable result exists — the lower FAILS LOUD rather
## than emit a word-copy against a broken read. (A str FIELD of a struct global works — global_str_field_write.)
build_reject_has reject_global_str_whole_assign "whole-value assignment to a mutable STR global"
## §8 @endian(big) field byte order (wire formats): a @packed struct with a big-endian u32/u16 field
## byte-reversed on store/load (bswap/rolw), the swap observed via native-order @offset overlay reads;
## x86_64-only sized loads/stores at byte offsets, so run_x86 (sweep-excluded).
run_x86 endian_struct 42
## §8 a field carrying BOTH @endian and @offset (in either order): the chain walker finds each lever even
## when another attribute sits adjacent to the field name (the former single-adjacent scan missed one);
## x86_64-only byte-precise layout, so run_x86 (sweep-excluded).
run_x86 endian_offset_struct 42
## §8 @repr(T) tagged-enum tag-representation lever: @repr(i32)/@repr(u8) enums constructed + matched;
## the match dispatch loads the tag at T's width (movslq/movzbl), x86_64-only, so run_x86 (sweep-excluded).
run_x86 repr_enum 42
## §8 @repr(T) NARROW in-memory tag STORE: a @repr(i32) enum's discriminant is written with `movl` (4
## bytes), not `movq` (8) — the STORE dual of the narrow tag load. The test seeds a sentinel in the 4
## bytes just past the i32 tag and reassigns the enum; a narrow store leaves the sentinel intact (a wide
## store zeroes it), so 20 (Blue) + 22 (sentinel survived) = 42. Address-of + raw ptr, x86_64-only.
run_x86 repr_tag_store 42
## §6.2 enum DISCRIMINANT PINS `= N`: a pinned variant's tag is the pinned value (not the positional
## index), following unassigned variants auto-increment from `N+1`, `match` on a pinned enum reaches the
## right arm, an un-pinned enum is unchanged (positional — the neutrality regression), and two variants
## resolving to the same value are rejected loud. The raw-tag reads are x86_64-only (address-of + raw
## ptr); the construct+match consistency test is cross-arch (swept).
run_x86 enum_disc_pin 42
run_x86 enum_disc_autoinc 42
run enum_disc_match 42
run enum_unit_local_cmp 42
run_a64 enum_unit_local_cmp 42
run_rv64 enum_unit_local_cmp 42
run_x86 enum_disc_unpinned 42
## Issue #16 / Types §6.2 — a duplicate effective discriminant is TARGET-INDEPENDENT ill-formedness, so
## every surface must refuse it. The check moved from the x86-only lower into `check`, which is why the
## three non-x86 rows below are new: they previously ACCEPTED this program and ran it to exit 0.
check_reject_has enum_disc_dup "two enum variants resolve to the same discriminant"
build_reject_has enum_disc_dup "two enum variants resolve to the same discriminant"
emit_reject_has aarch64 enum_disc_dup "two enum variants resolve to the same discriminant"
emit_reject_has riscv64 enum_disc_dup "two enum variants resolve to the same discriminant"
emit_reject_has wat enum_disc_dup "two enum variants resolve to the same discriminant"
build_reject_has enum_disc_expr_reject "enum discriminant pin must be a SINGLE integer literal"
run_x86 enum_disc_pin_bases 42
check_located reject_enum_disc_pin_overflow 3
## §8 @repr(T) representability: a non-integer tag type (@repr(str)) is a compile diagnostic — the build
## must fail loud (the alternative, a binary with a meaningless tag, is the forbidden silent miscompile).
build_reject repr_enum_bad
## §8: the same @repr representability rejection now carries a SOURCE LOCATION — sema mirrors
## `lower::validate_repr` faithfully (same `lower_layout` primitives: enum_repr_ty / repr_ty_is_integer /
## repr_ty_capacity), so `check` (which never ran `validate_repr`) now REJECTS AND LOCATES a bad @repr at
## the enum decl, not a bare undefined/unlocated abort. `@repr(str)` (non-integer) → line 4 of repr_enum_bad.
check_located repr_enum_bad 4
## §8: the NARROW-tag arm of the same representability check — an @repr(i8) enum with 129 variants
## exceeds i8's 128-value capacity (repr_ty_capacity), so the tag can't encode every discriminant. Located
## at the enum decl (line 7). Faithful sema mirror of validate_repr's variant-count > capacity branch.
check_located repr_narrow_reject_located 7
## §8 a layout attribute misplaced AFTER the `:` (`v : @offset(0) u32`) is a fail-loud parse error — the
## canonical surface is the PREFIX `@offset(0) v : u32`. Formerly silently dropped (a wrong-layout
## miscompile); now the build must be rejected (the forbidden alternative is a silent miscompile).
build_reject_has misplaced_attr_bad "must PREFIX the field"
## TYP-6 sibling: a plain direct call passing a user AGGREGATE (struct/enum) argument to a
## builtin SCALAR parameter (`f(s)` with `f := fn(x : u64)`, `s : S`) silently read the aggregate's
## word 0 as the scalar (rc=201, a wrong-but-valid result). The narrow call-arg soundness net now
## FAILS LOUD at build time; the forbidden alternative is that silent miscompile.
build_reject_has reject_agg_arg_scalar_param "check: type mismatch at line 10"
## Sibling soundness nets (TYP-6): the SAME aggregate-into-scalar silent miscompile via the other
## two sinks — a scalar-return fn `return`ing an aggregate Var (R1, delivered word 0 in %rax), and a
## scalar-annotated local bound to an aggregate Var (R2, stored word 0). Both must now FAIL LOUD.
build_reject reject_agg_return_scalar
build_reject_has reject_agg_local_scalar "check: type mismatch at line 9"
## Sibling soundness nets (TYP-6): the SAME aggregate-into-scalar silent miscompile via the three
## ASSIGNMENT-TARGET sinks — a scalar struct FIELD (`t.x = s`, P3), a scalar-element ARRAY element
## (`xs[0] = s`, P2), and a plain RE-ASSIGN into an existing scalar place (`G = s`, P1). Each kept only
## word 0 of the aggregate; all must now FAIL LOUD at build time.
build_reject_has reject_agg_field_scalar "check: type mismatch at line 11"
build_reject_has reject_agg_index_scalar "check: type mismatch at line 10"
build_reject_has reject_agg_reassign_scalar "check: type mismatch at line 10"
## REVERSE direction (TYP-6): a bare SCALAR literal into an AGGREGATE parameter (`f(42)` with
## `f := fn(p : S)`). A naive emit-time net could NOT reject this (it needs post-overload resolution,
## which the sema conformance gate — now on the build path — has), so it must FAIL LOUD at build too.
build_reject reject_scalar_arg_agg_param
## Types §4.6 / TYP-6 user CONVERSION-CONSTRUCTOR `@convert`: `Celsius(42)` (a non-brand target type)
## dispatches to the in-scope `@convert fn(u64) -> Celsius`; the struct result binds + a field read
## yields 42. x86_64-only register-return delivery, so run_x86 (sweep-excluded).
run_x86 convert_user 42
## @convert whose target struct is >7 words → routes the wide aggregate return through the sret path.
run_x86 convert_sret 42
## @convert whose TARGET is a builtin-conv name (`u64(structval)`): a struct operand routes to the
## @convert instead of the scalar lattice (which silently read word 0 — a miscompile now fail-loud).
run_x86 convert_to_builtin 42
## TYP-6 aggregate-operand soundness: a builtin conversion `u64(v)` over an AGGREGATE operand with NO
## matching `@convert` must FAIL LOUD (never a silent word-0 read). A named struct operand and a TUPLE
## operand (which `expr_type_span` cannot name — the tuple gap this closes) are both rejected; a tuple
## operand WITH an in-scope `@convert fn((i64,i64)) -> u64` routes to it (returns 42).
build_reject_has convert_agg_reject "needs a scalar operand"
build_reject_has convert_tuple_reject "needs a scalar operand"
build_reject_has reject_p0_f32_zeroarg "scalar conversion requires exactly one operand"
check_reject reject_p0_f32_zeroarg
emit_reject_has wat reject_p0_f32_zeroarg "scalar conversion requires exactly one operand"
emit_reject_has aarch64 reject_p0_f32_zeroarg "scalar conversion requires exactly one operand"
emit_reject_has riscv64 reject_p0_f32_zeroarg "scalar conversion requires exactly one operand"
run_x86 convert_agg_user 42
run module_mut_global 42
run module_mut_struct_global 42
run module_mut_array_global 42
run_x86 global_byte_array 42
run module_mut_global_snapshot 42
run atomics 42
run unchecked_block 42
run atomics_bitwise 42
run atomics_cas 42
run atomic_global_counter 42
run atomic_global_field 42
run atomic_global_elem 42
## concurrency primitives (Concurrency CC-1/4/7): OS threads over raw `clone` + a futex Mutex(T).
## These spawn real OS threads; each produced target is bounded by the shared runtime deadline, but a
## regression here still reports a concrete row failure — check them first if the run stalls.
run mutex_st 42
run thread_spawn 42
run thread_join_many 42
run mutex_basic 42
## CC-4 path 1 (message passing): a bounded futex+Mutex ring-buffer channel (std::channel).
run channel_spsc 42
run channel_mpmc 42
run channel_try 42
run channel_close 42
run channel_select 42
run channel_select_n 42
run module_global_init_expr 42
run for_range_backends 42
run for_range_regalloc 42
## regalloc 6c: `for x in Slice(u64) param` — base/len hoisted, indexed element load, register-resident loop
run for_over_slice_regalloc 42
## P3-RA-AGG bounded parent seam: a concrete `Slice(u8)` aggregate parameter is admitted only for the
## iterable loop body, where the allocator must use a zero-extending byte load. `read_index` in the fixture
## remains a text-path control seam; default and `ALATYR_RA=0` must both return 17.
run ra_agg_parent_slice 17
## P3-RA-AGG bounded follow-up: native-width `u64(x)` in the admitted `Slice(u8)` byte loop is an
## identity over the allocator's zero-extended word. The adjacent `u64(s[i])` helper remains text.
run ra_codec_slice_cast 17
## P3-RA-AGG next bounded follow-up: target-native `usize(u64(x))` stays a word identity after the
## admitted byte load. Direct indexing, a narrow-parameter call, nested binary conversion, and checked
## narrow arithmetic remain text/fail-loud controls.
run ra_codec_next_usize 17
## BYTES: a bounded byte-array return may be explicitly forwarded through another return before
## the caller reads its packed carrier. The adjacent wider/non-u8 return forms remain rejects.
run_x86 p1_bytes_param_forward_u8 42
check_accept p1_bytes_param_forward_u8
## BYTES consumer seam: a direct [u8; 4] return carrier is materialized into the existing
## aggregate temporary before a generic fixed-array parameter reads it by reference. The wider,
## signed, and non-byte controls remain located rejects inside the lower.
run_x86 p1_bytes_arg_consumer 42
check_accept p1_bytes_arg_consumer
run for_in_literal_struct_array 42
run for_in_global_array 42
run for_in_global_struct_array 42
run print_inferred_global_hole 42
run print_struct_display 42
run print_struct3 42
run print_struct_display_inferred 42
run print_tuple_display 42
run print_array_display 42
run print_global_struct_snapshot 42
run global_struct_by_ref_arg 42
run global_array_by_ref_arg 42
run global_struct_array_elem_read 42
## P0 statement-list walk: every backend must step over IndexAssign when recovering the later local
## declaration. The old wat variant stopped at xs[0] = 1 and misclassified the signed comparison.
run p0_stmt_walk_index_assign 42
run_wat p0_stmt_walk_index_assign 42
run_a64 p0_stmt_walk_index_assign 42
run_rv64 p0_stmt_walk_index_assign 42
## P0 parser: terminal statement-if branches must retain deref(place) = value stores.
## The parser previously classified these branches as value expressions and dropped the stores.
run p0_parser_if_deref_store 42
run_wat p0_parser_if_deref_store 134
run_a64 p0_parser_if_deref_store 42
run_rv64 p0_parser_if_deref_store 42
## P0 ABI: scalar in out write-back is by-place on AArch64/RV64, and the WASM backend
## traps on this unsupported pointer/ABI shape rather than returning a misleading value.
run p0_inout_scalar_writeback 42
run_wat p0_inout_scalar_writeback 134
run_a64 p0_inout_scalar_writeback 42
run_rv64 p0_inout_scalar_writeback 42
## P0 ABI: a final side-effecting call in a void function must not disappear.
run p0_void_tail_call_side_effect 42
run_wat p0_void_tail_call_side_effect 134
run_a64 p0_void_tail_call_side_effect 42
run_rv64 p0_void_tail_call_side_effect 42
## #175: a nested WAT enum match must retain the outer payload binding while an inner same-name
## binding shadows it only inside the inner arm. The fixture separately checks that the in-out caller
## value remains 7; plain `run` puts it in all cross-target sweeps, and `run_wat` executes WAT directly.
run issue175_wat_nested_enum_match 42
run_wat issue175_wat_nested_enum_match 42
## writing a whole element of a GLOBAL struct array from a struct VAR was a SILENT NO-OP: the mutable-global
## IndexAssign arm required BOTH the element and the RHS to be literals, and the generic tail then resolved the
## global's name through entry_of — which returns SLOT 0 for an absent name — and stored to a bogus %rbp offset,
## so the write vanished and the original .data words read back (const AND runtime index; a wide element too).
## rv64 MATCHes the first two, which is the real proof. A call RHS also works now; global→global copy, an
## if/match RHS and ENUM-element global arrays (whose .data image was wrong end-to-end) are fail-loud.
run global_struct_array_elem_write_var 96
run global_struct_array_elem_write_wide 46
run global_struct_array_elem_write_call 45
run global_struct_array_index_field 42
run global_struct_array_index_field_write 42
run global_struct_array_elem_write 42
## enum-element ARRAY GLOBALS end-to-end: the .data image emitted ONE `.quad global_init_value(…)` per element,
## but an enum literal has no scalar init value — so discriminants AND payloads came out 0 and the stride was 1
## word instead of `1 + max payload`; `GE[i]` then read/wrote from the MIDDLE of an element (silently 0 / 255
## until 8a61488 made it loud). Now imaged as `[disc, payload…, pad]` at `1 + enum_inst_words`, with the match
## scrutinee, the whole-element read and the element write all taking the stride from ONE helper, so they cannot
## disagree; the disc comes from `variant_index`, so `= N` pins are honoured. Covers nullary + 1- and 2-payload
## variants, const and runtime index, a CONST array, a generic element and @repr(u8) pinned discriminants.
run global_enum_array_rw 42
run global_enum_array_disc_repr 42
## the shapes that stay FAIL-LOUD rather than take one word from mid-element: an element in VALUE position,
## a call/by-ref/global-element/if-match RHS, and `for x in GE`.
build_reject_has global_enum_array_value_pos_reject "ENUM-element ARRAY GLOBAL element in a VALUE position is not supported yet (bind it first or match it directly) at line 9 in global_enum_array_value_pos_reject"
check_reject_has global_enum_array_value_pos_reject "ENUM-element ARRAY GLOBAL element in a VALUE position is not supported yet (bind it first or match it directly) at line 9 in global_enum_array_value_pos_reject"
emit_reject_has wat global_enum_array_value_pos_reject "ENUM-element ARRAY GLOBAL element in a VALUE position is not supported yet (bind it first or match it directly) at line 9 in global_enum_array_value_pos_reject"
emit_reject_has aarch64 global_enum_array_value_pos_reject "ENUM-element ARRAY GLOBAL element in a VALUE position is not supported yet (bind it first or match it directly) at line 9 in global_enum_array_value_pos_reject"
emit_reject_has riscv64 global_enum_array_value_pos_reject "ENUM-element ARRAY GLOBAL element in a VALUE position is not supported yet (bind it first or match it directly) at line 9 in global_enum_array_value_pos_reject"
build_reject_has global_enum_array_call_rhs_reject "module-level ENUM-element array GLOBAL"
build_reject_has global_enum_array_for_in_reject "for x in <ENUM-element ARRAY GLOBAL>"
run float_global 42
run print_float_global 42
run enum_global 42
run enum_global_direct_match 42
## nested generic-enum values: Option(Option(u64)) — nested inner match + bound-payload-as-call-arg
run nested_option 42
## nested-enum LITERAL with INFERRED type: `o := Option.Some(Option.Some(42))` binds the inner-enum payload
run nested_option_literal 42
run match_multibind_ptr 42
run int_narrow_conv 42
run inline_call 42
run inline_stmt_body 42
## Proposal #3 / Codegen §3.5 — aggregate parameters and builtin `bytes(...)` must survive direct @inline expansion.
run_x86 inline_aggregate_param 42
check_accept inline_aggregate_param
run_x86 inline_bytes_argument 42
check_accept inline_bytes_argument
check_reject reject_default_gap
check_reject reject_iife
## FN-6 EXPRESSION CALLEE — `fs[0](10)`, `fs[i](x)`, `t.fs[j](x)`, `(fs[0])(41)` now WORK (they used to silently
## drop the call and yield the callee's CODE ADDRESS — fs[0](10) → 17 — and were fail-loud in between). No AST
## node was added: such a call is an ordinary `Expr::Call` whose ARGUMENT 0 is the callee expression (the shape
## the UFCS desugar already builds), with the name span borrowed from the callee chain's ROOT variable so `check`
## resolves it as a local; the two are told apart by a site set keyed on the borrowed span's source offset.
## `(add1)(41)` is now simply the named call. Covers 2+ params, arg position, nesting, a float param, a param
## array, both instances inside a generic, inside a lambda, and across modules.
run fn_value_expr_callee 100
## FN-6 qualified function values: the parser stores only the tail name in a Var, so a
## same-module qualified value must still resolve to its code address before indirect call.
run fn_value_qualified 42
## …and the boundaries that stay LOUD: wrong arity through an expression callee, and a non-scalar (float/str/
## struct/enum) RETURN class, which is keyed on the callee NAME and cannot be resolved for an expression callee.
build_reject_has reject_call_expr_callee_arity "FN-6 - wrong ARITY"
build_reject_has reject_call_expr_callee_ret "FN-6 - a call through an expression callee"
## still rejected (no borrowable root NAME, so `check` cannot bind the callee): an element callee through a
## pointer `deref(pp)[0](10)`, a CALL-RESULT callee `mk()(41)` (its only root name is the inner callee, whose
## declared arity check then wrong-rejects), and the IIFE form.
check_reject reject_call_index_callee
check_reject reject_call_call_callee
check_reject reject_call_paren_callee
## an invalid generic-struct spelling `Box := struct(T : type) {…}` used to SIGILL the compiler with no
## diagnostic; now a located parse reject. (The valid form is `Box := fn(T : type) -> type { return struct {…} }`.)
check_located reject_struct_type_params 7
issue174_name_resolution_test
issue298_immutable_places_test
issue304_place_type_test
check_build_located reject_issue304_array_field_type 5 "type mismatch"
check_accept accept_issue304_array_field_type
check_reject reject_lambda_aggregate_return
check_reject reject_lambda_capture_escape
check_accept accept_param_default
## §5.1 parameter defaults are filled by lower::fill_program on ALL four backends (the x86_64 emit +
## the WAT/aarch64/riscv64 driver paths), so this runs everywhere — sweep-included via bare `run`.
run accept_param_default 42
check_accept generic_param_default
run generic_param_default 42
run operator_overload 42
run operator_compare 42
run operator_struct_result 42
run operator_vec2 42
## §2/OP-1: a routed user `@inline` struct operator over operands that are NOT simple typed locals —
## (a) a struct-LITERAL operand (`W(..) + W(..)`) and (b) an aggregate-PARAM operand added into an
## accumulator INSIDE a loop with no copy-to-local. Both were mis-typed by the route: (a) fell to the
## built-in scalar op (wrong value / SIGILL), (b) crashed the compiler / silently no-op'd (the
## cardinal silent-miscompile). x86_64-only aggregate operator delivery, so run_x86.
run_x86 routed_op_aggregate 42
run_x86 multiword_u128_add 42
## part 1 (Types §3/§7, TYP-2/TYP-10): `u128` as an ambient PRELUDE library
## multiword type — now the `u128 ≡ uint(128)` ALIAS of the generalized TYP-10 `uint(N)` recipe
## (lib/base/u128.al, little-endian `words`), used by BARE name — its `@inline` generic `+`/`-`
## ripple carry/borrow across the word boundary comparison-free (generate/propagate identity).
## 42 = carry-add + borrow-sub cover both dirs; x86_64-only (the multiword operator delivery), so
## run_x86 (sweep-excluded).
run_x86 u128_addsub 42
## §8.4 part 1b: the six COMPARISON operators on `u128` (`==`/`!=`/`<`/`<=`/`>`/`>=`), `@inline`
## generic, hi-word-to-lo-word lexicographic UNSIGNED — `<` is the comparison-free borrow ripple,
## `!=`/`>`/`<=`/`>=` the nested generic routes. Cases straddle the word boundary so a hi-first
## (or low-word-only) bug misses 42. x86_64-only, so run_x86.
run_x86 u128_cmp 42
## §8.4 part 2: MULTIPLY (`*`) on `u128`, `@inline` generic schoolbook (low N bits kept), column
## sums of low/high product halves + carry; the per-word high half is the x86_64 `mulq`→`%rdx`
## synthetic `mulhiq` inlined in the operator body. 42 = mulhi carry + cross term + plain products.
run_x86 u128_mul 42
## §8.4 part 3: DIVIDE (`/`) + REMAINDER (`%`) on `u128` — binary long division (shift-subtract)
## COMPTIME-UNROLLED over the N bits inside the @inline generic operator bodies (an @inline body
## cannot hold a runtime `while`; a comptime-param helper fn is not declarable), the conditional
## subtract branch-free via the borrow-ripple carry as a mask. 42 = boundary-crossing quotient
## (high word) + two low divides + an exact (=0) remainder.
run_x86 u128_div 42
## TYP-10 bit-glyph ops: the BITWISE operators `&`/`|`/`^` on `u128 ≡ uint(N)` — `@inline` generic
## per-word folds (lib/base/u128.al), no carry/cross-word ripple. `(a | b) & mask ^ c` over two
## words with `mask` selecting the low word only, so a cross-word leak or a missed route fails.
run_x86 uint_bitops 42
run operator_stmt_result 42
## §2: a struct arithmetic operator WITHOUT `@inline` (`+ := fn(a : Num, b : Num) -> Num`) — the
## resolver was `@inline`-only, so `a + b` fell to the scalar lowering and `r := a + b; r.v` read
## garbage (a silent miscompile). The non-inline fallback routes + sizes it like the @inline twin.
run operator_noinline 42
## SYN-4 (Grammar §2.6) binding-head exception: an operator-def decl on its own line after a
## bare-operand value decl (`base := 40` ⏎ `+ := fn(…)`) parses instead of folding into `40 + fn(…)`.
run operator_decl_own_line 42
## OP-1 bitwise glyphs `&`/`|`/`^` as user operator fns (parser name-gate admits kinds 34/35/36).
run operator_bitwise 42
run scalar_ops_library 42
run int_cmp_library 42
run width_wrap_arith 2
run section_global 42
run nested_struct_global 42
## WHOLE-VALUE assignment to a mutable AGGREGATE global (`G = S(…)` / `E.V(…)` / `[…]`). The bare-name
## global-write path stored a SINGLE word — for an aggregate global it dropped every word past word 0
## (and word 0 was an ADDRESS, not a value), a §Priority-1 silent miscompile. Now all words are copied to
## `.data` (structs/enums materialize through the width-safe agg-temp pool). src/+lib/ whole-assign only
## SCALAR globals, so the aggregate path is fixpoint-neutral. x86_64-only (the aggregate-global whole-
## assign `.data` copy is emitted by the x86 lower; the a64/rv64/wasm scalar-kernel backends do not model
## it and would silently miscompile it) → run_x86 (sweep-excluded), like the other agg-global-layout tests.
run_x86 global_agg_struct_whole_assign 42
run_x86 global_agg_array_whole_assign 42
run_x86 global_agg_enum_whole_assign 42
run_x86 global_str 42
run_x86 global_str_field_operand 42
run_x86 global_const_str_index 42
check_accept smoke
run early_return_result 42
check_accept early_return_result
run float 13
run float_abi 17
## TYP-13 / Types §9.1: an integer literal in an f32/f64 context is accepted only at an
## exactly representable boundary. The folded f32/f64 expression seam below proves that a constant
## integer expression is converted to an IEEE value before storage on every backend; the direct literal
## runtime seams prove the same for the non-expression path.
check_accept int_literal_float_context_f32
check_accept int_literal_float_context_f32_exact
run int_literal_float_expression 42
run int_literal_float_context_f64 1
run int_literal_float_runtime_f32 42
build_reject_has reject_typed_float_integer_f32 "check: type mismatch at line 2"
build_reject_has reject_typed_float_integer_f64 "check: type mismatch at line 2"
build_reject_has reject_typed_float_integer_u64 "check: type mismatch at line 2"
build_reject_has reject_typed_float_integer_u64_fraction "check: type mismatch at line 2"
build_reject_has reject_typed_float_integer_expression "check: type mismatch at line 2"
## Grammar §2.4 — decimal exponent spellings preserve their source through `.double`; malformed
## decimal/hex exponents and float separators reject during check. Hex-float syntax is check-only until
## the emitters can lower C-style hex text accepted by the native assembler.
run_x86 float_exponent 25
run_x86 accept_float_exponent_no_sign 100
check_accept float_hex_syntax
check_reject reject_float_exponent
check_reject reject_float_exponent_missing_digit
check_reject reject_float_hex_exponent
check_reject reject_float_hex_missing_exponent
check_reject reject_float_underscore
## float-bearing aggregates by value (x86_64): struct param/return + uniform & mixed float tuple params.
## The internal by-ref/GPR aggregate ABI is float-class-agnostic; this locks in that a float field/element
## reached through the aggregate reads on the xmm path (TYP-7). x86-only (float-element eek recovery).
run_x86 abi_float_aggregate 42
run float_ops 42
run signed_local_divmod 42
run stack_args 42
run stack_float_args 42
check_reject reject_dup_export
check_build_located reject_dup_export_value 5 "duplicate name"
check_reject reject_local_type_mismatch
check_reject reject_ptr_target
check_accept accept_ptr_target
check_reject reject_unbound
check_located reject_duplicate_name 2
check_reject reject_call_arg_type
check_reject reject_call_arity
check_reject reject_p1_call_result_conformance_direct
check_reject reject_p1_call_result_conformance_ufcs
check_reject_has reject_issue269_direct_option_result "type mismatch"
check_reject_has reject_issue269_option_result_payload "type mismatch"
check_reject_has reject_issue269_os_arena_result "type mismatch"
## Issue #269 residual / Types §4.1–§4.3 — direct qualified wrapper calls are rejected at the
## remaining scalar and named-struct return sinks; the existing annotated-binding rows above/below
## remain the independently landed annotation coverage.
check_reject_has reject_issue269_return_scalar "type mismatch"
check_reject_has reject_issue269_return_struct "type mismatch"
check_reject_has reject_issue269_tail "type mismatch"
issue269_os_arena_return_test
run accept_issue269_value_sink_control 42
## Issue #269 / Types §4.1–§4.3 / Declarations §3.1 — wrapper results are never implicitly projected
## into an explicitly annotated scalar or named-struct local. The local-binding case is separate from
## the already-landed call-argument fence; each fixture carries no searched diagnostic wording.
check_reject_has reject_issue269_annotated_result_scalar "type mismatch"
check_reject_has reject_issue269_annotated_option_scalar "type mismatch"
check_reject_has reject_issue269_annotated_result_payload "type mismatch"
check_reject_has reject_issue269_annotated_option_payload "type mismatch"
check_reject_has reject_issue269_annotated_local_result "type mismatch"
check_accept accept_issue269_annotated_wrapper_values
check_reject reject_p1_return_mismatch_direct
check_reject reject_p1_return_mismatch_ufcs
check_reject reject_p1_return_aggregate_builtin_cast
check_reject reject_p1_struct_to_str_direct
check_reject reject_p1_struct_to_str_ufcs
check_reject reject_p1_unknown_enum_variant
## Declarations §3.1 / Memory §1.6 — the types agree, but a plain `=` to an immutable local is a
## dedicated located diagnostic, not a type mismatch. Check and build must agree on the line and name.
check_build_located reject_immutable_write 3 "immutable binding"
check_accept check_struct_field_order
check_reject reject_check_unknown_struct_field
build_reject_has reject_export_mangled_collision "duplicate linker symbol at line 5"
check_reject reject_export_mangled_collision
emit_reject_has wat reject_export_mangled_collision "duplicate linker symbol at line 5"
emit_reject_has aarch64 reject_export_mangled_collision "duplicate linker symbol at line 5"
emit_reject_has riscv64 reject_export_mangled_collision "duplicate linker symbol at line 5"
check_reject reject_missing_result
check_reject reject_break_outside_loop
check_reject reject_continue_outside_loop
check_reject reject_return_type_mismatch
check_reject reject_atomic_ordering
check_reject reject_undefined_callee
check_reject reject_comptime_budget
check_reject reject_enum_local_as_scalar
check_reject reject_return_enum_as_scalar
check_accept accept_enum_local_used_as_enum
run accept_enum_local_used_as_enum 42
check_reject reject_nonexhaustive_match
check_accept accept_exhaustive_match
run accept_exhaustive_match 42
check_reject reject_nonexhaustive_value_match
check_accept accept_exhaustive_value_match
run accept_exhaustive_value_match 42
# Control Flow §5.4 — range patterns (a..b / a..=b) and OR-patterns (p | q | r).
run range_int_match 42
run or_pattern_match 42
run match_mixed_arm 42
check_accept accept_range_exhaustive
check_reject reject_range_nonexhaustive
build_reject_has or_pattern_bind_reject "OR-pattern alternative may not bind a payload"
check_reject reject_limit_unknown
check_accept accept_limit_no_opt
check_limit_named reject_limit_no_comptime 4 "@limits(no_comptime) violation"
check_accept accept_limit_no_comptime
run accept_limit_no_comptime 42
check_reject reject_limit_multi
check_reject reject_limit_no_alloc
check_accept accept_limit_no_alloc
run accept_limit_no_alloc 42
check_reject reject_limit_freestanding
check_accept accept_limit_freestanding
run accept_limit_freestanding 42
## FND-10 / Overview §3 — file limits must see ambient std capability calls and
## their trailing-expression/alloc-with forms, not only raw syscall/allocate names.
check_limit_named reject_limit_no_alloc_std_arena 4 "@limits(no_alloc) violation"
check_limit_named reject_limit_no_alloc_std_arena_tail 4 "@limits(no_alloc) violation"
check_limit_named reject_limit_freestanding_std_io 4 "@limits(freestanding) violation"
check_limit_named reject_limit_freestanding_std_io_tail 4 "@limits(freestanding) violation"
check_accept accept_limit_no_alloc_freestanding
run accept_limit_no_alloc_freestanding 42
## Types §4.2/§4.3/§4.6 + Declarations §3.1/§3.4 -- an annotated binding's declared type did not constrain
## its initializer, so `alatyr check` returned rc 0 with NO output for `x : u64 = "nope"` and the built
## program then produced a SILENT WRONG VALUE. The annotation was never misread (`x : u64 = 7` was always
## right): check_expr's arm list is non-exhaustive and reordered, so a string literal came back as tag 0 =
## UNKNOWN, and unknown is compatible with EVERYTHING by the poison-tolerance rule. The reject is a
## WHITELIST of proven-incompatible pairs, never `not tag_compat`, so an unresolvable sink stays accepted.
## The accept_* half is the load-bearing half: it locks that widening, brands, generic instances,
## `p : ptr(u8) = 0` (the MEM-7/8 usize<->ptr seam) and `[u8;N] = embed(...)` are NOT false-rejected --
## embed folds to a StrLit NODE while its spec surface is [u8;N], and it false-rejected in a first draft.
check_located reject_ann_str_into_int 6
check_located reject_ann_str_into_bool 3
check_located reject_ann_str_into_int_mut 3
check_located reject_ann_bool_into_int 5
check_located reject_ann_str_into_ptr 5
check_located reject_ann_array_into_int 4
check_located reject_ann_int_into_array 4
check_located reject_ann_global_str_into_int 4
check_located reject_ann_call_str_ret_into_int 8
check_located reject_ann_str_into_struct 6
check_located reject_ann_struct_into_str 4
check_accept accept_ann_str_binding
check_accept accept_ann_conforming
check_accept accept_ann_global_conforming
## CORRECTION: this was NOT a silent miscompile. `f("ok")` never LINKED -- overload_args_match left a
## StrLit a full wildcard, both candidates matched, resolution returned -1, no name suffix was emitted and
## `ld` reported an undefined reference. The driver's rc 14 for a link failure merely READ like `b.len()`
## answering 14, which fooled two independent readings. Fixed; now runs, so it is promoted from
## check-only to a real run.
run accept_ann_call_overloaded 9
check_accept accept_ann_brand_and_generic
issue299_brand_identity_test
run accept_ann_str_binding 9
run accept_ann_conforming 7
run accept_ann_global_conforming 9
run accept_ann_brand_and_generic 12
check_accept issue171_global_const_str
run issue171_global_const_str 42
## Types §4.2/§4.3 + Functions §2.3 -- a call ARGUMENT was not judged against its PARAMETER: 16 shapes
## passed `check` with rc 0 and no diagnostic, 12 producing a silent WRONG VALUE and 4 a silent SIGSEGV.
## The Call arm DOES compare via ty_compat -- what was dropped is the argument's LITERAL FORM: check_expr's
## arm list is non-exhaustive and reordered, so StrLit/BoolLit/ArrayLit/StructLit/EnumLit arguments came
## back tag 0 = UNKNOWN, and unknown is compatible with everything by poison tolerance. (An Expr::Num
## argument, whose arm DOES dispatch, was already caught -- see reject_call_arg_type.) Judged by the SAME
## ann_lit_incompatible whitelist as the annotated-binding half; anything unclassifiable stays ACCEPTED.
## The accept_* half is load-bearing: overloads, generics, variadics, in-out, defaults, brands, the
## MEM-7/8 usize<->ptr seam, `embed` into [u8;N] and UFCS must NOT be false-rejected.
## Functions §5 -- single-file `check` could not SEE a UFCS call: `check_files` built its PC with an EMPTY
## enum table, so `parser.al:2050` took `enums_known == false`, set is_ctor and parsed `Var.method(args)` as
## an EnumLit rather than a Call. EIGHT checks were escaping through that, six of them PRE-EXISTING (arity
## both directions, undefined callee, unbound receiver, and -- worst -- an ill-typed ORDINARY call nested in
## a UFCS argument list, because the whole argument subtree went unvisited). Each row was verified against
## its DIRECT twin, which rejected. The package path already did the two-pass parse; this gives the
## single-file path the same shape.
## Declarations §2.3 -- an unknown `@name` in DECLARATION-PREFIX position was consumed and DROPPED by the
## parser's prefix loop, so `@bogusattr X := 42` and, worse, a TYPO of a real attribute (`@pcked`) compiled
## clean: the property the author declared was silently replaced by none. The check lives in SEMA, against
## the RESOLVED DECLARATION SET, because the library attribute set is OPEN (CT-10) -- a parser known-list
## would turn away user-defined effectors. accept_userdef_attr is the load-bearing half.
check_located reject_unknown_attr_decl 11
check_located reject_unknown_attr_fn 7
check_accept accept_userdef_attr
run accept_known_attrs 42
## Types §9.1 -- an integer literal's representability in the type it takes from CONTEXT went unchecked
## below 64 bits: `x : u8 = 300` ran on a truncated 44. resolve_ty collapses every integer WIDTH onto one
## tag, so the width is read from the type NAME instead. Four sinks: annotated local, module-scope
## binding, call argument, and return. The accept_* pair locks every boundary value and all four bases.
check_located reject_lit_range_u8 9
check_located reject_lit_range_i8 4
check_located reject_lit_range_u32 3
check_located reject_lit_range_i64 8
check_located reject_lit_range_hex 4
check_located reject_lit_range_arg 10
check_located reject_lit_range_return 5
check_located reject_lit_range_global 4
run accept_lit_range_edges 42
run accept_lit_range_bases 42
## Declarations §3.4 / Types §9.1 — an unannotated literal uses native SIGNED, so 2^63 is rejected;
## the positive i64 boundary remains valid for inferred locals and module globals.
check_located reject_lit_range_default 6
run accept_lit_range_default_edges 42

## CT-12 / Comptime §2.6 — a failed CHECKED GUARD during comptime evaluation is a LOCATED compile-time
## diagnostic at the operation's site, never a deferred trap. `K : u64 = <u64 MAX> + 1` used to build
## green and die with a bare SIGILL only when a run-time path reached K; `x : i64 = <i64 MAX> + 1` ran
## to a silent WRONG value and `K : u8 = 200 + 100` materialized 300 in a u8. `unchecked` drops the
## OVERFLOW guard (the two's-complement wrap is defined and must still evaluate) but NOT division by
## zero or an over-width shift — the evaluator has no hardware behaviour to reproduce (I11).
check_build_located reject_comptime_overflow_global 8 "comptime overflow"
build_reject_has reject_comptime_overflow_named_constant "comptime overflow at line 5"
check_build_located reject_comptime_overflow_local 4 "comptime overflow"
check_build_located reject_comptime_narrow_overflow 5 "comptime overflow"
check_build_located reject_comptime_overflow_return 5 "comptime overflow"
check_build_located reject_comptime_overflow_array_element 2 "comptime overflow"
build_reject_has reject_comptime_overflow_array_element "comptime overflow at line 2"
check_build_located reject_comptime_call_arg_overflow 8 "comptime overflow"
build_reject_has reject_comptime_call_arg_overflow "comptime overflow at line 8"
check_build_located reject_comptime_call_arg_forward_overflow 4 "comptime overflow"
build_reject_has reject_comptime_call_arg_forward_overflow "comptime overflow at line 4"
check_build_located reject_comptime_div_zero 4 "comptime division by zero"
check_build_located reject_comptime_shift_width 3 "comptime shift out of range"
check_build_located reject_comptime_unchecked_div_zero 6 "comptime division by zero"
check_build_located reject_comptime_unchecked_shift_width 6 "comptime shift out of range"
## the OVER-REJECTION guard: a legitimate `unchecked` comptime wrap must still evaluate AND still carry
## its wrapped value at run time (src/ + lib/ hash code leans on exactly this), plus every boundary
## value that fits and must NOT be rejected.
check_accept accept_comptime_unchecked_wrap
run accept_comptime_unchecked_wrap 42
check_accept accept_comptime_call_arg_controls
run accept_comptime_call_arg_controls 42
check_accept accept_comptime_array_element_controls
run accept_comptime_array_element_controls 42
## Issue #268 / Comptime §§2.2, 9.1 + Declarations §3.1 + Grammar §130 — the bounded scalar binding
## slice: typed/inferred integer and bool bindings, a nullary user-enum binding, closed arithmetic, local
## use in a comptime-if, and scalar runtime use. The negative rows below keep runtime dependencies,
## reassignment, `comptime mut`, and a standalone top-level `comptime if` fail-closed.
check_accept issue268_comptime_binding
run issue268_comptime_binding 42
run_x86 issue268_comptime_if_u64_high 42
fmt_test_has_all issue268_comptime_binding 42 "comptime base : u64 = 5" "comptime inferred := base + 2" "comptime local : u64 = inferred + 1" "comptime flag := true"
check_accept issue268_comptime_rebind
run issue268_comptime_rebind 26
fmt_test_has_all issue268_comptime_rebind 26 "comptime x := 5" "x := 7"
check_reject_has reject_issue268_comptime_runtime "type mismatch"
check_reject_has reject_issue268_comptime_mut "comptime mut"
check_reject_has reject_issue268_comptime_reassign "immutable binding"
check_reject_has reject_issue268_comptime_top_level_if "standalone top-level"
check_reject_has reject_issue268_comptime_branch_escape "ambiguous call"
check_reject_has reject_issue268_comptime_branch_rebind "ambiguous call"
check_located reject_ufcs_arity_under 11
check_located reject_ufcs_arity_over 9
check_located reject_ufcs_undef_method 9
check_located reject_ufcs_unbound_recv 10
## check_reject, not check_located, deliberately: the conformance path locates these at the enclosing fn
## header rather than the call, identically to their direct twins. That imprecision is pre-existing and
## should not be baked into an assertion.
check_reject reject_ufcs_arg_str_into_int
check_reject reject_ufcs_arg_bool_into_int
check_reject reject_ufcs_nested_call_arg
run ufcs_call_checked 42
## Grammar §2.4 -- a PARSER located reject counted newlines from the BUFFER base rather than the module
## base, so the ambient stdlib text pulled in ahead of the module was counted too: an error on source line 3
## was reported as line 152 with a struct in the file, or 2369 with Option(ptr(u64)). The module name and
## the source snippet were always right, so rejects stayed findable -- the NUMBER was worse than useless.
## Six existing fixtures had their reported line corrected by this and are upgraded to check_located above.
check_located reject_int_lit_line_after_ambient 12
check_located reject_call_arg_str_scalar 11
check_located reject_call_arg_str_nominal 9
check_located reject_call_arg_bool_num 8
check_located reject_call_arg_array_num 6
check_located reject_call_arg_struct_str 9
check_located reject_call_arg_num_array 8
check_located reject_call_arg_bool_array 5
check_accept accept_call_arg_conform
## check-only ON PURPOSE: running it would lock a pre-existing overload-set link failure.
check_accept accept_call_arg_conform_wide
run accept_call_arg_conform 42
## §6 aggregate `==` must compare CONTENTS. A TUPLE parses as an ArrayLit and an ARRAY slot is kind 5, so
## `agg_value_var_words` -- which reads the slot KIND, not the type -- answered 0 and both fell to a
## single-word compare: `(5,7) == (5,9)` and `[5,7] == [5,9]` both read EQUAL. Tuple/array PARAMS were
## worse: they compared the caller's block ADDRESS. Routing to base::derive::eq is NOT possible (derive
## has no Tuple arm, its Array arm does not link, and a derive instance is keyed by a TYPE SPAN that a
## tuple literal does not have), so equality is emitted componentwise -- exactly what an unrolled derive
## would produce for single-word integer components.
run tuple_array_eq 42
run agg_elem_compare 42
check_accept agg_elem_compare
run_x86 agg_elem_compare_param 42
run_x86 checked_agg_elem_compare_param_oob 132
## §6 a Slice(T) view is a two-word {ptr,len} and `==` compared WORD 0, the POINTER: equal contents at
## different addresses read UNEQUAL, and two views of the same base with DIFFERENT lengths read EQUAL.
## A third bug sat underneath: `is_str_operand` accepted EVERY Expr::Slice, so a typed slice was already
## reaching the str route and byte-comparing `len` BYTES -- but a typed slice's len counts ELEMENTS, so
## [1,2,3] vs [1,9,3] compared three bytes of word 0 and read EQUAL. The fix is the word-granular twin of
## the str comparer, placed BEFORE the str route; `str` itself is untouched (a str local is ek 4 and a str
## sub-view has no array base, so the new classifier declines both).
run slice_eq 42
## the element kinds that cannot be word-compared stay LOUD rather than silently wrong.
build_reject_has reject_slice_ordering "ordering (< > <= >=) over a"
build_reject_has reject_slice_float_compare "float element needs the IEEE compare"
build_reject_has reject_slice_struct_elem_compare "struct/enum/str/pointer element needs base::derive::eq"
## Types §9.1 -- the `unchecked` type peel was ORDER-DEPENDENT: `infer_local_scalar_type`'s Bin arm took the
## FIRST typed operand, so `u64 + i64` recorded u64 and moved a pair containing a PROVEN-SIGNED member to
## unsigned, while `i64 + u64` stayed signed. Same program, operand order flipped, different answer. The
## refusal is narrow -- an opposite-signedness PAIR proves nothing -- rather than "both operands typed",
## which would drop the recorded type for `x := a + 1` over a narrow `a` (what the CG-6/I11 narrow wrap and
## the overflow guard read) and would flip `u64 + usize`, on which all four backends already agree.
run unchecked_mixed_signedness 42
## §9.1 — a bare integer literal inherits the proven unsignedness of its `u64` partner inside
## an `unchecked` arithmetic expression. All four backends now return 42; this used to be a normal-exit
## silent wrong value (3) on a64, rv64 and wasm.
run unchecked_literal_unsignedness 42
run_x86 signedness_array_elem 42
run_x86 signedness_slice_elem 42
run_x86 signedness_slice_local 42
run_x86 signedness_slice_variadic 42
## the components that CANNOT be done that way stay LOUD rather than silently wrong: nested tuples, str /
## float / struct / enum components, and ordering (`<`) over a tuple. A local plain-struct aggregate
## array element is covered by `agg_elem_compare`; concrete fixed-array params with plain native-scalar
## struct fields are covered by `agg_elem_compare_param`; enum/tuple/string and other aggregate element
## representations remain deliberately loud.
build_reject_has reject_agg_elem_compare "whole multi-word AGGREGATE ARRAY ELEMENT"
build_reject_has reject_tuple_str_compare "multi-word by-value TUPLE / ARRAY"
## Types §9.1 -- `s := unchecked (w + d)` then `s < w` compiled a SIGNED compare and answered FALSE for a
## high-bit u64. `infer_local_scalar_type` had arms for Var/Call/Field/Bin/Index but NONE for Unchecked,
## and `is_unsigned_expr` could see through neither `unchecked (...)` nor an arithmetic Bin with both
## operands proven. The peel is filtered to unsigned types ONLY: the parser ERASES a scalar bitcast, so an
## unfiltered peel saw `unchecked bitcast(usize, n)` as bare `n`, recorded isize, and flipped `c / d` from
## divq to idivq.
## an `unchecked` SCOPE changes only the VERIFICATION mode of what it wraps, never its TYPE, but
## the type scan had no arm for it, so `s := unchecked (w + d)` over u64 bound s UNTYPED and `s < w` fell to
## the always-SIGNED compare: `0 < 18446744073709551610` answered FALSE. Closed on x86 first and then on all
## three other backends, where the hole was IDENTICAL but the mechanism differs (they source-scan a `: uN`
## annotation instead of reading a slot table, so both the expression shapes AND the un-annotated binding
## needed recovering). 6 silent miscompiles per backend. The peel is PROOF-ONLY and unsigned-filtered: the
## parser ERASES a scalar bitcast, so an unfiltered peel would read `unchecked bitcast(usize, n)` as bare `n`
## and record the SOURCE type isize. Matches 42 on x86, a64, rv64 and wasm.
run unchecked_keeps_unsignedness 42
## Functions §5.1 -- overload_args_match narrowed a bare INT literal to int-scalar candidates and a bare
## FLOAT literal to float-scalar ones, but left a StrLit a full WILDCARD, so a two-candidate set that
## differs only by str-vs-int never resolved and emitted a bare label that failed to link.
run overload_str_literal_arg 42
check_reject reject_limit_no_unchecked
## FND-10 / I5+I9 -- the unit contract was ESCAPABLE: `@limits(no_unchecked)` rejected the EXPRESSION
## form but silently ACCEPTED the statement BLOCK form `unchecked { ... }`, at fn top level, inside
## if/for/while/match/comptime-if, and behind `break unchecked (...)`. The scan only RECURSED INTO
## Stmt::Unchecked instead of flagging it (its own comment asserted no block form existed, while
## parser.al emits exactly that node). Both enforcement paths are covered: the declared limit
## (check_reject) and the manifest ceiling (build_reject).
check_reject reject_limit_no_unchecked_block
build_reject_has reject_limit_no_unchecked_block "@limits(no_unchecked) violation"
check_reject reject_limit_no_unchecked_nested_block
build_reject_has reject_limit_no_unchecked "@limits(no_unchecked) violation"
check_accept accept_limit_no_unchecked
run accept_limit_no_unchecked 42
check_reject reject_limit_no_abstractions
check_reject reject_limit_no_abstractions_cast
check_reject reject_limit_no_abstractions_layout
check_reject reject_limit_no_abstractions_qualified_asm
check_reject reject_limit_no_abstractions_at_operand
check_reject reject_field_layout_attr
check_accept accept_limit_no_abstractions
run_x86 accept_limit_no_abstractions 42
## §10 linearity — use-after-forget: a mention of an @owning handle AFTER its forget() discharge
## is a use-after-consume error (reject); forget() as the terminal use is fine (accept).
check_reject reject_use_after_forget
check_reject reject_use_after_forget_branch
check_accept accept_forget_terminal
## §10 — use-after-free: a `_free`-tail discharge consumes its handle arg; a later mention rejects.
check_reject reject_use_after_free
check_reject reject_use_after_free_ufcs
check_accept accept_free_terminal
## §10 — leak-detection: an @owning handle created then never used (straight-line fn) is a leak.
check_reject reject_leak_owning
check_accept accept_owning_discharged
## §10 — leak-detection in a CONTROL-FLOW fn: an @owning handle used nowhere on any path is a leak.
check_reject reject_leak_owning_cf
check_accept accept_owning_discharged_cf
## Control Flow §9.3 / Memory §5.8 — a `defer`ed close discharges an @owning handle's linear obligation → accepted.
check_accept accept_defer_discharges_owning
## Memory §5 — dangling pointer: returning ptr(local/param) escapes a dead stack slot (reject); ptr(global) is fine.
check_reject reject_dangling_ptr
check_reject reject_dangling_ptr_tail
check_accept accept_ptr_global
## Memory §5.3.1 — store-escape: reassigning `ptr(<fn-local>)` into a module `mut` global (a static place
## that outlives it) is a forbidden upward flow (reject), incl. inside a nested branch; a same-scope
## `p := ptr(x)` binding is fine (accept + runs to 42).
check_reject reject_store_escape
check_reject reject_store_escape_branch
## Memory §5.3.1 — the companion escape: assigning ptr(<fn-local>) to an `out` parameter (a reference to
## the caller's place, which outlives the callee) also escapes upward (reject).
check_reject reject_store_escape_out
## Memory §5.3.1 — into a FIELD of a module mut global aggregate ("a field of any aggregate that
## outlives R") — same static-place sink reached through a field (reject).
check_reject reject_store_escape_field
check_reject reject_store_escape_field_path
run store_local_ptr_ok 42
## §6 aggregate `==` must compare CONTENTS, not the block ADDRESS. wat/a64/rv64 each fell through their
## aggregate guard for a shape with no named struct decl -- a TUPLE parses as an ArrayLit, and the a64/rv64
## Bin arm had no aggregate gate at all, so an aggregate PARAM compared the caller's block address and an
## ENUM compared word 0 (the discriminant) alone: `E.A(5) == E.A(9)` read EQUAL. All were normal-exit wrong
## values. The three non-x86 backends now REJECT the construct loudly (none of them has base::derive::eq),
## which is why these run as traps there and MATCH only on x86.
run agg_cmp_not_address 7
run agg_cmp_param_not_address 3
## §9.4 float rodata for a fn whose ENTIRE BODY IS AN EXPRESSION: the a64/rv64 `.Lflt` walk iterated
## Decl.body_stmts only, which is EMPTY for that shape (the body lives in Decl.value), so every math_* test
## rejected at `ld` on an undefined .Lflt label. Fixing it exposed a second gap on the same path: op 42
## (`not`) was in neither the cmp nor the arith set, so `if not (0.0 < x)` in std::math::sqrt emitted brk/ebreak.
run float_tail_expr_rodata 31
## Types §11 -- the decimal literal exactly 2**63 materialized as -8, so `i64::MIN < 0` was FALSE.
## NOT a lexer bug: the value parsed correctly and was corrupted by the compiler's own decimal
## RENDERER (`rt::sb_uint`), whose recursion guard `n >= 10` was lowered as a SIGNED compare because
## an integer LITERAL carries no type span. Guarding on `n / 10 != 0` makes it signedness-independent.
## Also covers 2**63-1, 2**63+1, 2**64-1, the hex spelling and the negative i64::MIN form.
run int_literal_2p63 42
## Stdlib §2.7 / §4 -- a signed minimum must render its full base-10 magnitude. `0 - i64::MIN`
## overflowed in `std::io::print_int`, after the sign byte had already been written. The exact
## stdout golden locks both the two's-complement boundary and the successful final write result.
run_x86_out print_int_i64_min 42
## Functions §7.1 / I11 — a call in STATEMENT position (result discarded) whose callee's TAIL name collides
## with the comptime-variadic `std::fmt::print` was routed into the `{}`-template desugar, which emits
## NOTHING when argument 0 is not a string literal: the whole statement — call, arguments, side effects —
## disappeared with no diagnostic. `callee_variadic_idx` resolved by tail name only, so `std::io::print`
## (one `str` param) was mistaken for `std::fmt::print` (variadic). The exit code counts the calls that
## actually ran (38 -> 42), so the gate does not rest on stdout; the golden locks the exact bytes.
run stmt_call_str_arg 42
run_x86_out stmt_call_str_arg 42
## The same defect with NO `str` and no view in sight: a user-declared `print := fn(x : u64)` shadows the
## prelude variadic and never ran — the program returned 0 instead of 42. Scalar-only, so it
## MATCHES on a64/rv64/wasm too, which is the cross-backend proof.
run stmt_call_shadow_print 42
## The two-word VIEW as a discarded call's argument — the shape the defect was first blamed on. It always
## worked; locked so a discarded call keeps emitting the same argument setup as a value-position one.
run stmt_call_view_arg 42
## A `{}`-template variadic `print` whose TEMPLATE is not a literal has nothing to expand, and emitting
## nothing deleted the statement. It must fail LOUD; `check` does not model the desugar, so build_reject.
build_reject_has reject_variadic_print_nonliteral "needs a string-LITERAL template"
## Grammar §2.4 / SYN-3 -- SILENT TRUNCATION of every literal form except decimal and plain 0x: the lexer's
## digit branch ended the number token at the first non-decimal byte, so everything after a base prefix or
## the first `_` became a separate identifier token the parser DISCARDED. 0b1000 -> 0, 0o777 -> 0,
## 1_000 -> 1, 0xF_F -> 15. A prefixed literal's body is now consumed GREEDILY so the parser -- which has a
## diagnostic channel, the lexer does not -- sees one complete token and can reject it located.
run int_lit_bases 42
run int_lit_separators 42
run int_lit_wide 42
## Types §9.1/§11 -- an out-of-range literal SIGILLed the compiler (checked multiply inside dec_val,
## rc 132, core dumped, zero output) instead of being the compile error the spec already mandates.
## The guard is derived from (2**64-1)/base so it can never itself overflow; dec_val's accumulation stays
## CHECKED deliberately -- trap loud beats wrap silent if a future path ever skips validation.
check_reject reject_int_lit_bad_digit
check_reject reject_int_lit_lead_sep
## DELIBERATE NARROWING: 0X/0O/0B uppercase prefixes are now rejected (0XFF used to yield 255). §2.4's
## terminals are lowercase and the spec spells out both cases where it means both (`exp ::= ("e"|"E")`),
## so lowercase-only is the reading. Nothing in src/, lib/ or test/ used it.
check_reject reject_int_lit_upper_prefix
check_reject reject_int_lit_overflow
check_reject reject_int_lit_overflow_hex
## Declarations §2.3 / Grammar §3.2 -- a LAYOUT attribute in declaration-PREFIX position was silently
## dropped: `@packed` before `P := struct{...}` gave size 24 (the word model) while the RHS spelling gave 7.
## The parser consumed and discarded it, and all three lowering lookups recovered their attribute by
## scanning FORWARD from the decl name, so nothing before the name was ever read. The fix also makes the
## un-attributed direct-scalar control use the CLAYOUT S4 natural size (8 here). The drop is
## BIDIRECTIONAL -- linkage/codegen/storage attributes (@export/@inline/@section) are honoured ONLY as a
## decl prefix and silently dropped in value position; that half is still open.
## NOT registered as fmt_test ON PURPOSE: `alatyr fmt` still drops the prefix spelling (verified here:
## run(fmt(x)) = 2 vs run(x) = 42), because this form only BECAME meaningful with this change. Recorded.
run attr_prefix_layout 42
check_reject reject_attr_prefix_repr_narrow
## Types §8 / Declarations §2.3 -- a DECLARATION-PREFIX `@packed` must enable the FIELD byte-layout
## attributes inside the body exactly like the value-position spelling. It did not: `sm_packed` was
## seeded false and set only by the VALUE-position consumer, so a legal `@offset` field was FALSELY
## REJECTED. (A false reject, not a silent value -- but it made the newly-honoured prefix spelling
## half-usable.) run_x86, not run: @packed byte layout is x86-only, and run_x86 is excluded from the
## sweeps' `^run [a-z]` grep.
run_x86 attr_prefix_packed_fields 42
## Declarations §2.3 -- an attribute the user WROTE must never be silently discarded. Each of these was
## accepted and thrown away without a word: @offset/@endian at type level (struct laid out un-attributed
## / native byte order), @niche (consumed, then died in the LINKER with `undefined reference`), and
## value-position @section (no .section directive emitted). Both spellings of each are locked so the two
## positions can never drift apart again -- that drift IS the bug: layout attributes worked only on the
## RHS, linkage/codegen/storage only as a decl prefix.
check_located reject_attr_offset_prefix 9
check_located reject_attr_offset_value 5
check_located reject_attr_endian_prefix 7
check_located reject_attr_endian_value 3
check_reject reject_attr_niche_prefix
check_reject reject_attr_niche_value
check_reject reject_attr_section_value
## @abi in prefix position stays REJECTED deliberately: @abi(naked) is recovered by a source scan that
## reads the VALUE position, so honouring the prefix spelling would honour @abi(syscall) while silently
## dropping @abi(naked) -- trading a loud reject for a silent one. Raised as a spec question instead.
check_reject reject_attr_abi_prefix
## Types §9.1/§11 -- ROOT of int_literal_2p63: an ORDERING compare between an UNSIGNED value and an
## integer LITERAL was lowered SIGNED (a literal carries no type span, so the "both operands provably
## unsigned" guard could never prove that side). Silently wrong at/above 2**63 on ALL FOUR backends:
## with n : u64 = 2**63, `n >= 10` was FALSE and `n < 100` TRUE. Covers both operand orders, all four
## orderings, u64/usize, a literal at/above 2**63 (whose own i64 word is negative), and the signed
## controls that must NOT flip (`x < -1` over i64 stays signed).
run cmp_unsigned_literal 42
## Issue #367 / Types §3.2 and Comptime §§1.4–1.6: typed comptime u64 locals are materialized into
## runtime comparisons without losing unsigned condition selection; the fixture covers all six operators,
## both operand orders, high-bit/max/small values, ordinary u64 controls, and signed i64 controls.
run issue367_comptime_u64_cmp 42
## Codec acceptance probes: nested enum and Slice(T) payloads must preserve their complete values through
## construction, return, matching, and a second call boundary; the specification's [T] slice spelling
## must not be accepted as a parameter/return fixed-array shape; and a range over a usize bound must retain
## unsigned comparison semantics.
run codec_nested_enum_payload 42
run codec_slice_payload 42
run_x86 slice_payload_element_access 42
check_accept slice_payload_element_access
check_located reject_codec_slice_sugar_param 1
check_located reject_codec_slice_sugar_return 1
run for_range_unsigned_bound 42
manifest_entry_test 42
interface_summary_test
single_file_start_test
manifest_limits_ceiling_test
manifest_limits_qualified_package_test
build_profile_flags_test
# a SINGLE-FILE package: package.al is the whole program - the entry, a helper fn and a mutable
# global are all ROOT-LEVEL and therefore unprefixed.
root_package_test root_single "T _start" "T bump" "D COUNT"
# a single-file package whose root declaration is `main`: the synthesized wrapper calls `main`.
root_package_test root_main "T _start" "T main"
# a default-source multi-module package (omitted source_dir defaults to `src`): package.al is ONLY the
# manifest, so nothing is unprefixed and the modules keep `<module>__<fn>` - discovered from inside the
# directory too.
root_package_test flat_modules "T _start" "T main__main" "T util__answer"
root_package_test nested_modules "T _start" "T main__main" "T geometry__vec__answer"
# Modules §8 / Tooling §2.4 — PATH DEPENDENCIES. `dep_declared` DECLARES a path dependency it never
# references (declaring one must not move the root package's own emission — it used to abort module
# discovery and fail the link on an undefined `main`); `dep_alias_use` reaches it through the
# dependency's ALIAS namespace (`d::math::answer()`), whose module is named `d__math` so the call
# mangles onto `d__math__answer`, never a flat `math__answer`. Both consume test/package/dep_lib
# (a library package with no `main`, never built on its own) and exit 42.
root_package_test dep_declared "T _start" "T main__main"
root_package_test dep_alias_use "T _start" "T main__main" "T d__math__answer"
root_package_test dep_lib_nested_use "T _start" "T main__main" "T d__lib__thing__answer"
## Proposal #13 / STD-1 — a non-root module may instantiate the ambient Result prelude without
## importing std/alloc from the root; check, run, artifact exit, and module/linker boundaries are locked.
root_package_test result_nonroot_prelude "T _start" "T main__main" "T lib__go"
## Modules §3 + MOD-12 — a module global crossing a module boundary. A descendant may name an ancestor's
## global bare (`pub` or not); anyone may name a `pub` one through a path; a SIBLING's non-`pub` global is
## a located reject. Before this, a bare ancestor read silently returned 0, `TAB[2] = 30` from a submodule
## smashed the stack (SIGSEGV), and a shadowed name resolved to the WRONG declaration in both spellings.
root_package_test module_global_ancestor  "T main__main" "T geo__child__run" "T geo__deep__leaf__run" "D geo__COUNT" "D geo__TAB" "D geo__MSG"
root_package_test module_global_qualified "T main__main" "T other__run" "D geo__G" "D geo__TAB" "D geo__MSG"
root_package_test module_global_shadow    "T main__main" "T geo__child__run" "D geo__G" "D geo__child__G"
## Landed 2026-08-19 with the module-global namespacing but never registered anywhere until now.
root_package_test module_global_collision "T main__main" "T left__sample" "T right__sample" "D left__VALUES" "D right__VALUES"
## Proposal #4 / Memory §7 — sibling globals with the same spelling remain distinct for byte arrays
## and scalar values, and bytes(str) works both as a bound view and a global initializer.
root_package_test module_global_collision_bytes "T main__main" "T left__pick" "T right__pick" "D left__VALUES" "D right__VALUES"
root_package_test module_global_collision_scalar "T main__main" "T left__limit" "T right__limit"
## FN-6 qualified function value across sibling modules: direct and indirect `hex::encode` calls
## must select hex rather than the same-tail base64 declaration and both package entry paths agree.
root_package_test fn_value_qualified "T _start" "T main__main" "T main__apply" "T hex__encode" "T base64__encode"
## Modules §§4.1/6.1 — a named function-value alias keeps both the defining module and defining tail:
## `h := lower::a::a_helper; h()` must call `lower__a__a_helper`, not an undefined alias symbol in
## `lower__b` (or a caller-module fallback). The row also proves reachability retains the resolved fn.
root_package_test qualified_fn_alias "T _start" "T main__main" "T lower__b__run" "T lower__a__a_helper"
issue11_signature_type_name_test
issue11_package_type_name_test
## Modules §§4.1/4.1.1 — a one-element listed projection after a bare module alias must remain a
## declaration: `strbuf := rt` followed by `(Expr) := ast` must not be parsed as a call `rt(Expr)`.
root_package_test one_element_projection "T _start" "T main__main"
run_x86 global_str_bytes_view 42
check_accept global_str_bytes_view
run_x86 global_bytes_initializer 42
check_accept global_bytes_initializer
## Modules §3 for a BARE CALL — the callee counterpart of the module-global family above. `mod_head_matches`
## matched only the calling module (or a last-segment lib path), never the ANCESTOR CHAIN, so a bare call
## took the FIRST same-named declaration in decl order: an unrelated module's non-`pub` duplicate, which §3
## makes unnameable from there. Measured on the frozen seed: `module_fn_ancestor` returned 12
## (`call aother__helper`), `module_fn_shadow` 32 (`call aother__bump`). A generic instantiation had the same
## defect with the opposite tie-break (LAST wins). The reject halves, and the whole-program invariant over
## the compiler's own emitted GAS (`scripts/callee_module_check.sh`), live in scripts/package_cli_test.sh.
root_package_test module_fn_ancestor "T main__main" "T geo__child__run" "T geo__deep__leaf__run" "T geo__helper"
root_package_test module_fn_shadow   "T main__main" "T geo__child__run" "T geo__child__helper" "T geo__bump"
## Modules §3 + Types §4.1 for a bare TYPE NAME — the type counterpart of the callee family above, and the
## defect that blocked the file split. `struct_decl_of`/`enum_decl_of` took no naming module at all and
## settled same-named candidates by declaration ORDER (LAST wins — the opposite tie-break of the callee
## fallback's FIRST-wins), so a child's `Box.size()` sized a SIBLING's struct. One shape carried BOTH
## tie-breaks at once (a struct literal: the parser table first-wins, the lower last-wins), and the
## `@require` target ran the WRONG PREDICATE — a trap, not a value. Measured on the frozen seed:
## `module_type_ancestor` returned 7, `module_type_shadow` 90. The reject halves and the whole-program
## invariant over the compiler's own GAS (`scripts/type_module_check.sh`) ride package_cli_test.sh.
root_package_test module_type_ancestor "T main__main" "T geo__child__run" "T geo__deep__leaf__run" "T geo__always_ok"
root_package_test module_type_shadow   "T main__main" "T geo__child__run" "T geo__edge__run"
mod8_root_duplicate_test
qualified_generic_package_test
standard_tuple_global_module_test
ambig_pub_test
ambig_enum_collision_test
check_located reject_qualified_generic_unknown 3
no_input_diag_test
tool16_no_vendor_test
tool11_output_validation_test
tool13_path_validation_test
multi_target_layout_test
tool17_source_check_test
tool17_target_kind_test
tool17_target_code_size_test
tool17_declaration_target_when_test
tool17_prelude_visibility_test
ext_test package_cli_test
## The toolchain-spawn regression (scripts/env_size_test.sh). An environment too large for one read used
## to truncate mid-entry, after which `build_envp` wrote its terminating word 8 bytes PAST its reservation
## — into the next allocation, which held the `$PATH` probe strings — so `execve` got a malformed envp and
## failed EFAULT. The compiler then reported "the assembler rejected the emitted assembly" although `as`
## had never run, which is why a driver defect read as a codegen regression for weeks. This also locks the
## split diagnostics: could-not-run (19) / rejected-the-input (13) / not-on-PATH (11).
ext_test env_size_test
## Issue #344: keep the inferred `ptr(u8)` pointee-width boundary fixture private so the
## regression exercises the generated 483/484-byte source-recovery boundary without adding corpus
## oracle rows. The script also asserts the emitted x86 load width.
ext_test issue344_pointee_width_test
## Issue #342: keep the aggregate Slice parameter source-recovery boundary fixture private so the
## regression exercises both name/type spacing beyond the old window without adding corpus oracle rows.
## The helper also checks the three backend twins while preserving their existing fail-loud aggregate path.
ext_test issue342_aggregate_slice_test
## The ambient source scan used to read every user file at a 512 KiB cap while `src/lower.al` is ~1.8 MB,
## so the library-injection scan saw 28% of the largest module — output-neutral by luck, not by design.
ext_test source_read_cap_test
## `osplit_on` took its Arena BY VALUE, so its allocations did not advance the caller's `off` and its buffer
## was dead on return — safe only while it returned a bool. This locks the in-out signature and the
## caller-place call so nobody reintroduces the aliasing shape.
ext_test osplit_arena_mode_test
native_test_runner_test
tool5_contract_test
## TOOL-7 (Tooling §4.1) — a program that declares its OWN entry still builds with it as the ELF entry
## and drops its `@test` item (TOOL-5's half). x86_64-only (a hand-written entry). The complementary
## `alatyr test` half — the test artifact supplies the runner's entry and links neither the manifest
## `Target.entry` nor a source `_start` — is checked in scripts/package_cli_test.sh (test_entry(...)).
check_export tool7_entry_start 42 _start
check_export tool7_entry_main_reached 42 _start
fmt_test fmt_sample 42
## §5.4 fmt: scalar range match arms (lo..hi / lo..=hi) render + grouping parens preserved (precedence).
fmt_test fmt_range_prec 42
## §5 fmt: two silent-miscompile locks — unary-minus grouping parens `-(a+b)`, and `f(args).field` arg-drop.
fmt_test fmt_neg_paren 42
fmt_test fmt_call_field 42
## §5 second corpus sweep: 15 more files fixed, 0 regressions. The worst renders were the ones that still
## LOOK fine -- `@alloc(ar) h := P(...)` became `alloc_into(...)` so the marker vanished and the prelude
## stopped being injected; a qualified type arg made the enum-table lookup fail and SWALLOWED every
## following declaration; `bitcast(B, x)` grew a `ptr(...)` and a spurious `unchecked` (42 -> SEGV); a
## `comptime N : u64` parameter lost its modifier (42 -> SIGILL); and `[u64; 3]` rendered as
## `[u64, u64, u64]`, which the assembler then rejected.
fmt_test_has fmt_prefix_attrs 42 "@packed pub Pb"
fmt_test_has fmt_array_fill 42 "sum_gen([u64; 3], xs)"
fmt_test_has fmt_alloc_attr 42 "@alloc(ar) h := P(x = 30, y = 2)"
fmt_test_has fmt_qualified_tryable 42 "Result(usize, ser::SerError).Ok(0)"
fmt_test_has_all fmt_qualified_return 42 "alloc::strbuf::StrBuf" "return tail() + 2"
fmt_test_has fmt_bitcast_targets 42 "y := bitcast(B, x)"
fmt_test_has fmt_test_decl 42 "@test(\"a test with no return type at all\")"
fmt_test_has fmt_comptime_param 42 "fn(comptime N : u64, a : w(N)"
fmt_test_has fmt_compfor_typeinfo_arg 42 "comptime for f in typeinfo(B).fields"
fmt_test_has fmt_comptime_arm_template 42 "comptime for v in typeinfo(T).variants { T.(v)(pa) =>"
## the OWN-LINE prefix attribute -- the form that became MEANINGFUL the same day fmt was last swept, and
## so was silently erased by it (the packed declaration changed from size 7 to the natural size 24).
## Lockable now only because the fixture's two in-body notes
## were hoisted into its header: fmt cannot retain an in-body comment, and fmt_test asserts fidelity.
fmt_test attr_prefix_layout 42
## §5 fmt has NO fail-loud channel, so a WRONG RENDER IS A SILENT MISCOMPILE. The corpus check
## (run(fmt(x)) vs run(x) + idempotence over every test/*.al) found the formatter silently miscompiling
## roughly one file in six; these lock the eleven roots. Each `_has` needle pins the exact construct that
## was erased, so a regression cannot pass by rendering something merely parseable.
## The parser desugars EVERY dot call to Call(method,[recv,...]) and fmt's enum table holds only the
## file's own enums, so all stdlib Option/Result construction rendered as `Some(Option, 40)`.
fmt_test_has fmt_ufcs_dot 42 "r.unwrap()"
## FieldDecl keeps only name+type+arity: `@packed`/`@align`/`@repr` vanished and a discriminant PIN
## (`A = 5`) took the following variant with it. Rendered verbatim now.
fmt_test_has fmt_agg_decl 42 "@packed struct"
## by-NAME struct construction re-attached the names POSITIONALLY -- values stayed put while names moved,
## the worst shape of all because the render still compiles.
fmt_test_has fmt_struct_lit_names 42 "D(b = 3)"
## Expr::Num carries an i64 printed signed, so u64 MAX rendered as `-1`, which re-parsed to
## `unchecked 0 - 1` and SIGILLed.
fmt_test_has fmt_big_literal 42 "18446744073709551615"
fmt_test_has_all fmt_literal_spelling 42 "0x2A" "0o52" "0b101010" "1_000" "0xffffffffffffffff"
fmt_test fmt_recursive_match_array 42
## `unchecked` is a p_factor PREFIX: the block form lost its braces, and Unchecked(Bitcast) double-emitted
## and GREW on every pass (the non-idempotent root).
fmt_test_has fmt_unchecked_forms 42 "unchecked bitcast(ptr(mut Pt), base)"
fmt_test_has fmt_unchecked_postfix 42 "unchecked (x.u)"
## an APOSTROPHE inside a struct-body comment opened a char literal in skip_balanced_group and swallowed
## the body, dropping @offset/@endian (42 -> 2).
fmt_test_has fmt_agg_body_comment 42 "@offset(3) b3"
## nothing is recorded on the Decl, so @convert/@require/@abi/@export/@extern and `when` guards were all
## dropped -- including a BODYLESS @extern that came back WITH a body, defining the symbol it imports.
fmt_test_has fmt_decl_attrs 42 "@convert fn"
fmt_test_has_all value_position_attrs 42 "@export(\"value_export\")" "@inline fn"
fmt_test_has fmt_when_guard 42 "when target.arch == Arch.x86_64"
## a generic TYPE FUNCTION was normalized into a generic enum decl and rendered UNPARSEABLE (the second
## pass segfaulted); an EnumLit keeps only the base name span, losing the instance's type args.
fmt_test_has fmt_generic_typefn 42 "Either(A, B).L(a)"
## the `:=`/`=` probe accepted only a literal `=`, so `x -= 50` became `x := x - 50` and SHADOWED the
## local; a trailing `when` guard and a `u32.require(p)` alias were both dropped.
fmt_test_has fmt_decl_tails 42 "u32.require(is_nonzero)"
## Comptime §2.4 / Tooling §4.3 -- the formatter retains the semantic embed path while the existing
## x86 byte fixtures prove the baked payload remains exact. The needle is source text, not a comment.
fmt_test_has embed_bytes 42 'embed("test/embed_fixture.bin")'
fmt_test_has embed_byte_storage 42 'embed("test/embed_fixture.bin")'
fmt_test_has embed_typed_bytes 42 'embed("test/embed_fixture.bin")'
fmt_check accept_call_arg_conform_wide
## §5 fmt: ROOT fix (driver enum-name table) — call.field + call.METHOD(args) preserve args (workaround missed .method).
fmt_test fmt_call_method 42
## §5 fmt: precedence grouping (keep needed parens, drop redundant), nested match-arm body, nested aggregate lits.
fmt_test fmt_precedence 42
fmt_test fmt_nested_match 37
fmt_test fmt_nested_agg 52
## §5 fmt: `pub` visibility is preserved (recovered by source-scan; idempotence alone can't catch a drop).
fmt_test_has fmt_pub 42 "pub "
fmt_test fmt_types 42
## §5 fmt: a generic type decl `Opt(T) := enum { … }` keeps its `(T)` type-parameter header (was dropped → made
## the decl non-generic + non-idempotent); recovered by source-scan. Asserts the header survives.
fmt_test_has fmt_gen_enum 42 "(T)"
fmt_test fmt_array 42
fmt_test fmt_comments 42
fmt_test fmt_comptime 42
fmt_test comptime_if 42
fmt_test fmt_comptime_match 42
fmt_test_has comptime_match_bare 42 "Scalar => comptime match k"
## P2-FMT-AST: statement-match comptime variant templates survive canonical emission; the arm-local
## reassignment needle locks `=` versus a second `:=`, while idempotence + exit 7 lock executable behavior.
fmt_test_has fmt_comptime_match_template 7 "local = local + 1"
fmt_test fmt_comptime_for 42
fmt_test fmt_float 42
fmt_test fmt_loop_expr 42
fmt_test fmt_try 42
## unary minus re-emits as `-x` (not the `unchecked 0 - x` desugar), idempotent + still runs: 42.
fmt_test fmt_neg 42
## a typed local binding `name : T = v` re-emits WITH its `: T` annotation (was dropped), idempotent: 42.
fmt_test fmt_typed_bind 42
fmt_test range_slice 42
fmt_test enum_global 42
fmt_test fmt_str_match 42
fmt_test fmt_typed_global 42
# fmt_limits now carries a leading `##` block: fmt_decl_anchor anchors comment attachment at the `@` of
# `@limits(` (name_start points inside it), so the block round-trips (comment fidelity) + the directive.
fmt_test fmt_limits 42
# §5 module-directive decls: import aliases (incl. `pub`) + a bodyless `@abi(syscall)` fn round-trip
# through fmt (was fail-loud "unsupported declaration kind" for both).
fmt_test fmt_module_directives 42
# §5 statement-form coverage: fmt now handles range/iterable `for`, `loop`/`break`/`continue`, `a[i] =`,
# `a[i].f =`, nested-field `o.p.x =`, and `deref(p) =` (was fail-loud "unsupported statement form"). The
# reused tests add AllocWith (alloc_with_elision) and the `unchecked { }` block (unchecked_block).
fmt_test fmt_statements 42
## §5 fmt (FN-6): an EXPRESSION-callee call is an ordinary Call whose ARG 0 is the callee — fmt rendered it
## literally as `fs(fs[0], 9)`, a different program. The needle locks the spelling (both forms build and run,
## so the exit alone cannot catch it). fmt also checks the arg-0 chain STRUCTURALLY, because the site set is
## keyed on a source OFFSET, unique only within one file, while `alatyr fmt <package>` formats many files in
## one process off that one global set.
fmt_test_has fmt_expr_callee 80 "fs[0](9)"
## §5 fmt (§9.3): `defer` round-trips as SURFACE syntax — it used to come back as the internal `__defer(…)` /
## `__deferblk()` markers, which survived only because the lower re-intercepts those names.
fmt_test_has fmt_defer 123 "defer mark(3)"
fmt_test_has fmt_defer 123 "defer {"
## §5 fmt: deep places + Slice(T) / [Struct; N] fields. The real lock is the NO-INITIALIZER local
## `mut xs : [A; 2]`, which was re-emitted as `= 0` — a silent miscompile (79 → 1).
fmt_test_has fmt_deep_places 79 "v : Slice(u64)"
## §5 fmt: an enum global ARRAY initializer + a wide-enum `return W.Some(<7-word struct>)`.
fmt_test_has fmt_enum_forms 49 "mut GE := [E.A(1), E.B(2)]"
## issue #393 / Control Flow §5.2 + Tooling §4.3 — an enum-variant PATTERN must come back out in the
## spelling the author wrote. `parse_pat_alt` keeps only the LAST path segment of `Result::Ok(h)` /
## `AllocError.OutOfMemory`, and both arm emitters re-emitted that bare tail, so `fmt` DELETED every
## qualifier. On this fixture that is fatal, not cosmetic: `cli::ambient_paths` injects the base
## prelude by scanning the source TEXT for the bare result-type name, and the patterns hold its only
## occurrence — the formatted output lost `Arena`/`allocate`/`AllocError` and stopped compiling, with
## `fmt` still exiting 0. The needles pin all three spellings in BOTH emitters; the single-line arm
## list also pins the bare arm staying bare, which the exit code alone cannot see.
fmt_test_has_all issue393_fmt_variant_qualification 42 "Result::Ok(h) => {" \
    "Result::Err(e) => {" "AllocError.OutOfMemory => {" "AllocError.SizeTooLarge => {" \
    "match t { Tag::Red => 1, Tag.Green => 2, Blue => 4 }" "Tag::Blue => {" "Tag.Blue => {"
## §5 fmt: the PARAMETER surface — head-token-only types (`ptr(mut R)`→`ptr`, `Slice(u64)`→`Slice`,
## `[u64;2]`→`u64`, `fn(u64)->E`→`fn`), erased `in out`/`out` modes and erased defaults. These were the
## worst of the family: formatting silently turned deref_field_write 42→0 and fn_value_enum_ret 42→211.
fmt_test_has fmt_param_types 42 "in out y : u64"
fmt_test_has fmt_param_types 42 "f : fn(u64) -> E"
## the same two, end-to-end on the EXISTING fixtures whose formatted form used to be a different program.
fmt_test_has deref_field_write 42 "ptr(mut Rec)"
fmt_test_has dyn_closure 42 "ptr(mut s1)"
fmt_test alloc_with_elision 42
fmt_test unchecked_block 42
# §5 expression-form coverage: fmt now round-trips a MULTI-PAYLOAD enum variant decl (verbatim payload
# group), the boolean short-circuit `and`/`or` + prefix `not` (parser op bytes 40/41/42), a string literal
# with an ESCAPE (raw-source span vs the decoded StrLit length), a GENERIC-INSTANCE struct literal
# (base-name field-name recovery), and a DESTRUCTURE import `(A, B) := mod` (retained verbatim span).
fmt_test fmt_operators_enum 42
# SYN-4 (Grammar §2.6): fmt round-trips an operator-def decl written on its own line after a bare-operand
# value decl (the binding-head boundary) — idempotent AND still builds+runs (the old parser errored here).
fmt_test operator_decl_own_line 42
# TUPLE spellings + a `mut` struct field. Every form here shares its AST node with an ARRAY form —
# `(3, 4)` and `[3, 4]` are both `Expr::ArrayLit`, `p.0` and `p[0]` are both `Index(base, Num(N,0,0))` —
# and `mut x` on a struct field is recorded NOWHERE in the AST, so fmt must read the written bracket and
# marker back out of the source. Before this, `t.1.0 = 20` rendered `t[1][0] = 20`, which the parser does
# not accept as a nested element write, so the SECOND fmt pass read fmt's own output as two bare statements
# and flattened the rest of the function; and a dropped field `mut` made a `typeinfo(T).fields` derive count
# zero mutable fields, returning 41 instead of 42 — a formatter silently changing what a program computes.
fmt_test_has_all fmt_tuple 42 "p : (u64, u64) = (3, 4)" "t.1.0 = 20" "a.0[2] = 7" \
    "mut t := (10, (99, 88))" "mut a : ([u8; 4], u64) = ([1, 2, 3, 4], 9)" \
    "cnt((u64, u64))" "mut x : u64"
fmt_test_has_all comptime_typeinfo_field_mutable 42 "mut x : u64"
## Tooling §4.3.3 — the 100-COLUMN limit, measured in Unicode scalars. Two assertions in each fixture,
## because a wrapper is wrong in both directions: the LONG constructs must fold (the `  epsilon_value :
## u64,` / `    epsilon = 500000,` / `    and alpha2 == 2` needles are one-item-per-line at the wrapped
## indent, and none of them existed before the fix), and the SHORT ones must stay put (`small_array_value
## := [1, 2, 3]`, `small_sum := alpha1 + alpha2` — those two are present before AND after, which is the
## point: they catch a fix that just wraps everything). `fmt_test` itself re-formats its own output, so
## the wrapped form is also asserted IDEMPOTENT — a trailing comma must reparse as the grammar's §2.6
## trailing `item-sep`, or pass 2 would drift.
fmt_test_has_all fmt_wrap_100col 42 "  epsilon_value : u64," "    epsilon = 500000," \
    "    700000000," "    555555555555555555," "small_array_value := [1, 2, 3]" \
    "narrow := fn(a : u64, b : u64) -> u64 {"
fmt_test_has_all fmt_wrap_binchain 42 "    and alpha2 == 2" "    and alpha6 == 6" \
    "small_sum := alpha1 + alpha2" "  total_sum := wide("
## Both spellings, so a fix cannot pass by always writing `mut`: the parser keeps only the POINTEE span
## for a sub-word bitcast target, so `mut` was absent from the AST and fmt wrote `ptr(u8)` for both —
## the same program today, a different SOURCE, and a build break the day pointer mutability is enforced.
fmt_test_has_all fmt_bitcast_ptr_mut 42 "bitcast(ptr(mut u8), addr)" "bitcast(ptr(u8), addr)"
## `fmt` rendered an `else if` chain as a NESTED `} else {` plus an inner `if` one level deeper. That inner
## `if` then sits last in a block, where the parser reclassifies a trailing `if` with single-expression arms
## as an if-EXPRESSION — so pass 2 reparsed a different tree than pass 1 wrote. All six non-idempotent
## modules of the compiler's own source were that ONE cause, and it was not cosmetic churn: where the arms
## are `deref(dp) = v` stores, the if-expression reparse keeps only the bare place and the STORE IS DROPPED —
## `fmt` was silently rewriting the program. The chain now renders flat, which is also the spelling Control
## Flow §4 names. `run` alongside `fmt_test_has_all` because the formatted program must still run.
fmt_test_has_all fmt_elseif_chain_stmt 42 "} else if "
run fmt_elseif_chain_stmt 42
## §4.2.3 caps the LINE, but the verdict only ever saw the construct: a parameter list that fits and a
## pending `-> R` that does not still overflows, and an inline value-`if` whose condition fits while
## ` { 42 } else { 1 }` pushes the line past 100 does too.
fmt_test_has_all fmt_wrap_if_expr_cond 42 "    and bravo_counter == 1" "    and alpha_counter != 9 {" "    42" "  } else {" "    1"
run fmt_wrap_if_expr_cond 42
fmt_test_has_all fmt_wrap_params_ret_reserve 42 "  h : u64," ") -> u64 {"
run fmt_wrap_params_ret_reserve 42
## The existing chain fixture was registered as `run` only, so it could not see the rendering — it was
## classed NONIDEMPOTENT by the arbiter while the gate stayed green.
fmt_test_has_all elseif_chain_value_form 42 "} else if "
## NOT registered through `fmt_test_has_all`: `display_tuple` carries an INTERIOR comment
## (`## expected: "(3, 4)" — 6 bytes.`) and fmt drops it, because the lexer emits no newline tokens and only
## leading top-level `##` blocks survive — the corpus-wide interior-comment gap (272 of 1 357 fixtures
## lose one), a reseed-class fix in
## `src/lexer.al`/`src/lexrt.al`. Its tuple rendering is covered by `fmt_tuple` above and by
## `scripts/fmt_corpus.sh`, whose ALLOW table records the residual instead of hiding it. Registering it here
## would make the gate red for a defect we have decided not to fix yet, which is worse than either.
fmt_test_has_all display_tuple_agg 42 "t : (Pt, u64) = (Pt(x = 1, y = 2), 9)"
fmt_test_has_all tuple_lit_arg 42 "display((u64, u64, u64), (10, 20, 30), sb)"
fmt_test_has_all tuple_nested_write 42 "mut t := (10, (99, 88))" "t.1.0 = 20" "t.1.1 = 12"
fmt_test_has_all standard_tuple_byte_component 42 "mut t : ([u8; 4], u64) = ([1, 2, 3, 4], 9)" "t.0[2] = 42"
## 34, not 42: this fixture's own header says 3*10 + 4.
fmt_test_has_all comptime_typeinfo_n 34 "cnt((u64, u64, u64, u64))"
# §5 CROSS-MODULE struct literal: field names recovered by source-scan when the struct decl is in an
# imported module (bare + generic-instance + qualified head), instead of fail-loud.
fmt_crossmod_test
fmt_package_test
flush_status_test
arena_init_mmap_failure_test
fmt_large_input_test 1200000 42
check_located reject_located_unbound 8
## Issue #194 / Tooling §5: a semantic diagnostic must name the line of the offending expression,
## not the enclosing function declaration. The line-7 fixture has two complete declarations before
## main, so reporting the last declaration is not an accidental pass.
build_reject_has reject_sema_line_1 "check: unbound name at line 1 in reject_sema_line_1"
check_reject_has reject_sema_line_1 "check: unbound name at line 1 in reject_sema_line_1"
build_reject_has reject_sema_line_3 "check: invalid at line 3 in reject_sema_line_3"
check_reject_has reject_sema_line_3 "check: invalid at line 3 in reject_sema_line_3"
build_reject_has reject_sema_line_4 "check: invalid at line 4 in reject_sema_line_4"
check_reject_has reject_sema_line_4 "check: invalid at line 4 in reject_sema_line_4"
build_reject_has reject_sema_line_7 "check: invalid at line 7 in reject_sema_line_7"
check_reject_has reject_sema_line_7 "check: invalid at line 7 in reject_sema_line_7"
## structural rejections now carry the fn's location (was "location not tracked"): a missing result
## and a mismatched `return <literal>` (whose Num node has no span → the fn-name catch-all locates it).
check_located reject_missing_result 1
check_located reject_return_type_mismatch 1
check_located_multi
## parse errors now carry a source location too (was a bare rc 9): a malformed decl on line 3.
check_parse_located reject_parse_located 3
## §5: the parse diagnostic now renders the EXPECTED token kind from the `ParseErr` payload (reachable
## after the multi-word enum-return fix) — `@` where a name is expected, `bar` where `:=` is expected.
check_parse_expected reject_parse_located 3 "expected a name"
check_parse_expected reject_parse_expected_assign 7 'expected `:=`'
## §3 / Functions §7.1: a comptime-variadic `fn(args : ...)` whose body walks the pack with
## `comptime for` — `sum(10, 20, 12)` unrolls to 42 (monomorphized, expanded at the call site).
## MOD §6.3: @export emits an exact linker symbol at the fn entry (exit 42 + `nm` shows the global).
check_export export_symbol 42 alatyr_answer
run value_position_attrs 42
check_accept value_position_attrs
check_export value_position_attrs 42 value_export
check_inline_value value_position_attrs value_position_attrs__add
## MOD §6.3 on the WAT backend (the fourth backend): @export emits a WASM `(export "name" (func $f))`
## entry — the module still runs to 42 under wasmtime, and the export entry is present in the WAT.
run_wat export_symbol 42
check_wat_has export_symbol '(export "alatyr_answer"'
run_wat value_position_attrs 42
check_wat_has value_position_attrs '(export "value_export"'
## MOD §7: @extern import routes calls to the external symbol; paired with @export it links internally.
## @extern/@export call routing now on ALL FOUR backends. The three register-ISA backends (x86_64 +
## aarch64 + riscv64) link the @extern to the internally-@export'd sibling in the same object, so
## extern_call RUNS to 42 there. The WAT backend routes the call to a WASM `(import "env" "sym" …)`
## instead — correct FFI emission, but WASM resolves imports from the HOST, not internally, so the
## paired-internally extern_call module is structurally valid yet unrunnable under a bare wasmtime
## (missing host import). It is therefore NOT swept (a bare `run` would flag the unsatisfied import as
## a miscompile); WAT fidelity is checked structurally by check_wat_has (the import entry is present
## and wat2wasm accepts the module). run_x86/run_a64/run_rv64 are sweep-excluded (grep `^run [a-z]`).
check_wat_has extern_call '(import "env" "shared_impl"'
run_x86 extern_call 42
run_a64 extern_call 42
run_rv64 extern_call 42
## WIDE-ENUM SRET return (enum {disc,payload} total > 8 words) — a64 via x8 indirect result, x86 via the hidden
## result pointer. Now CROSS-BACKEND: x86 and a64 MATCH, wasm MATCHes, rv64 traps (all accepted by the sweeps).
## (x86 previously fail-loud on the literal form and SILENT-0 on the var form — both fixed with the SRET routing.)
## an ENUM LOCAL passed as a call ARGUMENT: a callee's enum param slot holds a POINTER to the caller's
## {disc,payload…} block, but a64's arg paths only knew struct/array/slice locals, so an enum local fell to the
## scalar path and its word 0 (the DISCRIMINANT) was passed as the pointer → raw SIGSEGV for narrow AND wide
## enums. Fixed on all three a64 arg paths. x86/a64/wasm MATCH 43, rv64 traps.
run enum_local_by_ref_arg 43
## WIDE-ENUM SRET call-ARG + TAIL-FORWARD. Now CROSS-BACKEND: x86 was a SEGFAULT (call-arg) and a SILENT 0
## (tail-forward) until a destination was wired for the hidden result pointer. x86/a64/wasm MATCH, rv64 traps.
run enum_sret_wide_call_arg 22
run enum_sret_wide_tail_forward 22
## `match <enum call>` with NO intervening binding. The TAIL VALUE spelling stored only disc + payload[0], dropping
## every later payload word (SILENT: N.Two(10,11) bound (a,b) as (10,0)); the WIDE (SRET) callee has no return
## registers at all and SEGFAULTED in both spellings. x86 MATCHes; a64/rv64/wasm trap.
run enum_match_call_scrut 50
run enum_sret_wide_match_call 32
## the same two SRET shapes at a second width, cross-verified by the rv64 lane — ALL FOUR backends agree
## (x86 = a64 = rv64 = wasm), which is what proved the x86 fixes rather than merely making the fixtures pass.
run enum_sret_wide_arg 16
run enum_sret_wide_tail 38
run enum_sret_wide_scalar 48
run enum_sret_wide_disc 75
run enum_sret_wide_local 30
## FFI (spec 150 §FN-9): C-ABI foreign calls — link an Alatyr program against a pure C stub object.
## `scalar_call` proves the harness + the scalar ABI (a,b,c in rdi/rsi/rdx = our internal ABI). The
## `struct_arg` test exercises the SysV struct-by-value INTEGER classing: a 16-byte all-integer struct
## in TWO regs (p.x->rdi, p.y->rsi; sumpt = p.x - p.y is ORDER-SENSITIVE) + a 1-eightbyte struct in
## ONE reg. x86_64-only (the C ABI is arch-specific), so run_ffi is sweep-excluded (grep `^run [a-z]`).
run_ffi scalar_call 42
run_ffi struct_arg 42
## Bounded sub-word aggregate seam: SysV packs two consecutive `u8` fields into one INTEGER eightbyte.
## The process exits with 51 because the fixture's mathematical answer is 307 (`307 mod 256`).
run_ffi struct_u8_arg 51
## Issue #168: the exact two-u8 packed shape must cross both aggregate directions. Each echo fixture
## exercises its direction's argument and return path, and both language sides read both fields.
run_ffi issue168_u8_pair_to_c 68
run_ffi issue168_u8_pair_from_c 68
## The bounded slice must not widen the old located refusal: two u16 fields remain unsupported.
build_reject_has ffi/issue168_u8_pair_unsupported "selfhost: @abi(c) aggregate with a non-eightbyte-aligned field"
## Increment 2 — FLOAT/SSE class. `float_call`: f64 scalar args in %xmm0/%xmm1 + an f64 RETURN read
## from %xmm0 (subd = a - b, ORDER-SENSITIVE). `float_mix`: MIXED i64+f64 scalar args on INDEPENDENT
## SysV counters (i,j->rdi,rsi ; x,y->xmm0,xmm1). `struct_float_arg`: an all-double struct D{f64,f64}
## by value in %xmm0/%xmm1 (SSE eightbytes) + a mixed M{i64,f64} splitting one INTEGER (%rdi) + one
## SSE (%xmm0) eightbyte. `struct_ret`: aggregate RETURN <=16B — an all-integer Pt{i64,i64} in
## %rax:%rdx + an all-double D{f64,f64} in %xmm0:%xmm1, each field read back + subtracted (swap-sensitive).
run_ffi float_call 42
run_ffi float_mix 42
run_ffi struct_float_arg 42
run_ffi struct_ret 42
## Increment 3a — MEMORY class (struct > 16 bytes). `struct_big_arg`: a 24-byte Big{i64,i64,i64}
## passed BY VALUE ON THE STACK (16-aligned area; sumbig = a + b - c, order/value-sensitive).
## `struct_big_ret`: a 24-byte Big RETURNED via SRET (hidden %rdi result pointer; the callee writes
## {a,b,c} into the caller's destination local, all three fields read back as a - b + c).
run_ffi struct_big_arg 42
run_ffi struct_big_ret 42
## Increment 3b — RECEIVING side: an exported `@abi(c)` Alatyr fn CALLED FROM C (its SysV prologue
## reads params from the SysV registers, its return rides the classed result registers). Each round-
## trips Alatyr -> C -> Alatyr = 42. `recv_scalar`: two i64 params (%rdi,%rsi) -> %rax. `recv_float`:
## two f64 params (%xmm0,%xmm1) -> %xmm0. `recv_struct`: a 16-byte all-integer Pt{i64,i64} BY VALUE
## in %rdi,%rsi (segfaults if read as the internal by-ref pointer). `recv_struct_ret`: an all-integer
## Pt{i64,i64} RETURNED in %rax:%rdx. `recv_struct_ret_sse`: an all-double D{f64,f64} RETURNED in
## %xmm0:%xmm1 (the classed-return remap; alt_mkd SWAPS its args so a missing remap yields 30 not 42).
run_ffi recv_scalar 42
run_ffi recv_float 42
run_ffi recv_struct 42
run_ffi recv_struct_ret 42
run_ffi recv_struct_ret_sse 42
## Increment 3c — the remaining C-ABI corners. `scalar_stack_args`: 8 integer args (>6) — args 7,8
## spill onto the STACK (arg7 at the lowest address). `sse_stack_args`: 9 f64 args (>8) — the 9th
## spills onto the stack. `str_arg`/`enum_arg`: a str / a <=16B enum passed BY VALUE, classed into
## two INTEGER eightbytes (an enum has no float fields). `recv_struct_big`: an @abi(c) fn RECEIVING a
## >16B struct BY VALUE on the caller's stack. `recv_struct_big_ret`: an @abi(c) fn RETURNING a >16B
## struct to C via SysV SRET (hidden %rdi result pointer, struct written up-growing, ptr in %rax).
run_ffi scalar_stack_args 42
run_ffi sse_stack_args 42
run_ffi str_arg 42
run_ffi enum_arg 42
run_ffi recv_struct_big 42
run_ffi recv_struct_big_ret 42
## Increment 3d (spec 50 §7.3) — C-VARIADICS (the final @abi(c) codegen corner). A callee whose last
## param is a bare `...` rest under @abi(c) is a C-variadic: the call passes fixed args + N extra
## variadic args, each classed by its OWN expression type (integer -> next int reg/stack, float ->
## next XMM/stack), and emits `movb $<n>, %al` (n = XMM regs used) before the `call` (SysV variadic
## requirement). `variadic_int`: three `long` varargs summed via va_arg -> 42 (%al = 0). `variadic_
## mixed`: a mix of long + double varargs (the two doubles ride %xmm0/%xmm1 -> %al MUST be 2) -> 42.
run_ffi variadic_int 42
run_ffi variadic_mixed 42
## MOD-9 (Modules §7.5 / Manifest appendix §3.5) — manifest-driven foreign-library LINKING. `dynm`:
## a `libs = [Lib(name="m", link=LinkMode.dynamic)]` package links libm dynamically (`cc -nostartfiles
## … -lm`), calls `sqrt(1764.0)` -> 42. `statstub`: the hermetic-static DEFAULT — a local `.a` archive
## absorbed by `ld -static … -L<dir> -lstub`, `add1(41)` -> 42. x86_64/manifest-specific (sweep-excluded).
run_link dynm 42
run_link_static statstub 42
run_library_target objectlib object 42
run_library_target staticlib static_lib 42
production_test_dce
abi_reachability_dce
library_dce_scope
## CT / Comptime §7: the `when <comptime-predicate>` DECLARATION-GUARD. Two companion `answer` fns +
## two `bonus` inferred constants gated by complementary target predicates; the FALSE-guarded decls
## (one calling a nonexistent fn) are dropped before name-resolution/emission (Phase B §9), so the
## program builds+links+runs to 42 instead of a duplicate-label / undefined-symbol failure. The fold
## targets x86_64 (like `comptime if`), so run_x86 (sweep-excluded).
run_x86 when_guard 42
## ARCH-IDENTITY (Tooling §2.7 + CT-5): `target.*` is the RESOLVED SELECTED machine model, so EVERY backend
## must fold `target.arch` to the machine it emits FOR and must honour a `when` declaration guard.
## aarch64/riscv64/wat folded `target.arch` as `x86_64` — "so the sweep compares like-for-like" — and ignored
## `Decl.when_cond` entirely, which is why the library could not express an arch gate and `lib/std/thread.al`
## reached `as` with x86 mnemonics on every backend. Deliberately a plain `run` (sweep-INCLUDED, unlike
## `when_guard` above): every arch-gated body returns 42, so it MATCHes on x86/a64/rv64 and traps cleanly on
## wat, whose machine v1's `Arch` enum does not name (WASM is additive, FND-6). The pre-fix aarch64 emit of
## this same program dies at `as` on a duplicate `tag` label.
run when_guard_arch 42
## CT / Comptime §7: the `when`-guard EXTENDED to TYPED bindings + struct/enum TYPE decls (CT-5). Same
## fold+drop as the fn form; the parser now attaches `Decl.when_cond` on these decl shapes too. Each
## folds against x86_64, so run_x86 (sweep-excluded). BINDING: a typed `val : u64 = 42 when x86_64`
## (kept) + `= 100 when aarch64` (dropped, declared LAST so last-match would give 100 if not dropped)
## → 42. STRUCT: 2-field `Cfg when x86_64` (kept) + 5-field `Cfg when aarch64` (dropped LAST); `Cfg.size()`
## = 16 → 16+26 = 42 (66 if the false decl survived). ENUM: `Sh.Answer(u64) when x86_64` kept, `when
## aarch64` variant dropped; builds+runs to 42 with the false-guarded enum excluded.
run_x86 when_guard_binding 42
run_x86 when_guard_struct 42
run_x86 when_guard_enum 42
## CT-4/CT-5: a comptime PREDICATE on a GENERIC fn (`when size(T) <= 8`) gates INSTANTIATION — the
## guard is folded per-instance at monomorphization with `T` = the concrete type. ACCEPT: `pick(u64,42)`
## (size 8 <= 8) → instance emitted → 42. REJECT: `pick(Big,42)` (size 24 > 8) → instance dropped →
## `pick__Big` undefined → build fails loud (build_reject). x86-focused generic emission, so run_x86.
run_x86 when_predicate 42
build_reject when_predicate_reject
## CT-4/CT-5: sema mirrors the size-predicate fold to give `check` a SOURCE-LOCATED reject (not a bare
## undefined-symbol LINK error) when a generic `when size(T)` guard folds FALSE for a call's concrete
## type-arg. `pick(Big, 42)` (Big a 3-word struct, size 24 > 8) → the guard folds FALSE → `check` rejects
## AND locates the call (line 12). The faithful-SUBSET boundary: sema folds only size/struct-enum, so the
## is-KIND / count / named-predicate rejects below stay LINK-time (build_reject), never wrongly check-reject.
check_located when_reject_located 12
## CT-4/CT-5: a STRUCTURAL is-KIND predicate — `when match typeinfo(T) { Struct(_) => true; _ => false }`
## (the spec's `TypeInfo`-tagged-enum surface, appendix §4.1) gates INSTANTIATION by T's KIND. ACCEPT:
## `pick(S,42)` (S a struct → kind Struct → 42). REJECT: `pick(u64,42)` (scalar → kind Scalar ≠ Struct →
## instance dropped → `pick__u64` undefined → build fails loud). x86-focused generic emission, so run_x86.
run_x86 when_predicate_kind 42
build_reject when_predicate_kind_reject
## CT-4/CT-5: the sema when-guard fold-mirror now also covers the is-KIND form, so `pick(u64,42)`
## (u64 a concrete scalar → kind Scalar ≠ Struct) is rejected by `check` with a SOURCE-LOCATED diagnostic
## at the call site (line 11), not only as a link-time undefined symbol. Faithful subset: sema folds the
## kind only for a PROVABLY-CONCRETE type-arg (declared struct/enum/brand, or a recognized scalar/ptr/str/
## fn/array/tuple spelling); an abstract enclosing type-param stays UNFOLDED → admit → never a wrong reject.
check_located when_predicate_kind_reject 11
## CT-4/CT-5: a MULTI-TYPE-PARAM predicate — `when size(V) <= 8` folds against the SECOND type-param's
## instance type. ACCEPT: `pair(u64,u32,42)` (size(u32)=4<=8 → 42). REJECT: `pair(u64,Big,42)` (size(Big)=24>8
## → `pair__u64__Big` dropped → undefined → build fails loud); a build that resolved size against the leading
## `K` would wrongly succeed, so the reject guards the 2nd-param substitution. x86-focused, so run_x86.
run_x86 when_predicate_2tp 42
build_reject when_predicate_2tp_reject
## CT-4: a NAMED comptime PREDICATE as the bound — `is_small := fn(T:type)->bool { size(T) <= 8 }` used as
## `when is_small(T)` ("a constraint is an ordinary comptime fn(type) bool"). The instantiation fold INLINES
## the predicate's single trailing bool expr (its `T` bound to the call's type arg → the concrete instance).
## ACCEPT: `pick(u64,42)` (is_small(u64) → size 8 <= 8 → 42). REJECT: `pick(Big,42)` (size 24 > 8 → instance
## dropped → `pick__Big` undefined → build fails loud). x86-focused generic emission, so run_x86.
run_x86 when_named_pred 42
build_reject when_named_pred_reject
## CT-4: the sema fold-mirror INLINES a named comptime predicate too — `when is_small(T)` resolves the
## callee, inlines its single bool body under the type-arg binding, and folds — so `pick(Big,42)` is rejected
## by `check` with a LOCATED diagnostic at the call site (line 15), not only at link. Same faithful-subset
## boundary as the size/is-kind forms (a not-yet-monomorphized arg stays admitted).
check_located when_named_pred_reject 15
## CT-4/CT-5: a structural FIELD-COUNT bound — `when typeinfo(T).fields.len >= 2` (the spec's
## `TypeInfo.Struct{fields:[Field]}` surface, appendix §4.1), the count folded per-instance. ACCEPT:
## `pick(S,42)` (S a 2-field struct → 2 >= 2 → 42). REJECT: `pick(One,42)` (1-field struct → 1 < 2). The
## sema fold-mirror folds this in the two-pass BUILD path (`-o` / sema-on-build), where the reject is a
## SOURCE-LOCATED `check` diagnostic (line 13) — so `build_reject` stays green. It is intentionally NOT a
## `check_located` test: the single-pass `check` SUBCOMMAND parses with an EMPTY enum table, so the parser's
## `is_generic_enum_ctor` rewrites the postfix `typeinfo(T).fields.len` to `Field(Var(typeinfo), …)`, ERASING
## the `(T)` type-arg — so `check` alone cannot recover T to fold, and safely admits (never a wrong reject).
run_x86 when_field_count 42
build_reject when_field_count_reject
## same shape: a build_reject fixture that `check` used to accept. check and build now agree.
check_located when_field_count_reject 13
## CT: `typeinfo(T).n` comptime member count (struct field / tuple component) as a comptime-for bound.
run comptime_typeinfo_n 34
## CT-6: Field.type is a comptime type value supplied to a generic field derive. The mixed u64/u32
## struct makes a stale enclosing-type or first-field-type substitution fail loudly. Register it on
## every emitter; the architecture helpers soft-skip only when their cross-toolchain is unavailable.
run comptime_typeinfo_field_type 42
run_a64 comptime_typeinfo_field_type 42
run_rv64 comptime_typeinfo_field_type 42
run_wat comptime_typeinfo_field_type 42
## CT-6/TYP-9: concrete (non-generic) ordinary struct projection through a comptime Field. This
## closes the backend gap where CompField was only unrolled inside a generic mono instance.
run comptime_typeinfo_field_projection 42
run_a64 comptime_typeinfo_field_projection 42
run_rv64 comptime_typeinfo_field_projection 42
run_wat comptime_typeinfo_field_projection 42
## Aggregate Field values remain outside this bounded scalar slice and must fail loud at lower time.
build_reject_has reject_comptime_typeinfo_aggregate_projection "comptime field projection of an aggregate"
check_wat_has reject_comptime_typeinfo_aggregate_projection "unsupported comptime-field access"
## CT-6: `Field.offset` is comptime metadata, using the same byte/word layout calculators as value
## access. Covers ordinary word layout, @packed byte layout, and a standard direct byte-array layout.
run_x86 comptime_typeinfo_field_offset 34
## CT: the SPEC-LITERAL nested forms `typeinfo(T).fields.len` (struct field count) and
## `typeinfo(T).variants.len` (enum variant count) as comptime-for bounds — the enum case is net-new.
run comptime_typeinfo_fields_len 42
run comptime_typeinfo_variants_len 42
## Comptime capability queries (Comptime §7): inspect an operand without evaluating it,
## folding the bounded resolution predicate to a bool before lower. Both true and false paths, plus side-effect suppression,
## are covered. Malformed arity is a check-time rejection.
check_accept compiles_module_query
run compiles_value_query 42
## QUERY/CT-6: the build-path query mirror must agree with ordinary scalar `v.(f)` Field
## projection. `sum_projection` proves the ordinary call path; the query checks the same u64 field
## true and the incompatible str sink false, without evaluating either operand.
run query_typeinfo_field_projection 42
## QUERY/CT-6: the capability-query mirror preserves aggregate field types without entering the
## ordinary aggregate value-position emitter, which remains fail-loud until its ABI is unified.
run query_typeinfo_aggregate_projection 42
run query_typeinfo_generic_instance 42
run query_qualified_public 42
run query_module_alias 42
run compiles_query 41
run compiles_type_mismatch 42
run resolves_query 42
run query_no_eval 42
run query_unselected_branch 42
run query_rollback 42
run query_aggregate_compiles 42
run query_aggregate_negative 42
run query_aggregate_no_eval 42
run query_constructor_binary_positive 42
run query_constructor_binary_negative 42
check_reject reject_constructor_binary
check_reject reject_query_arity
## CT: implicit generic type-arg inferred from a struct-literal value arg (resolution + instance-tag agree).
run generic_structlit_infer 42
## CT: a struct-literal-inferred generic instance dedups against the same instance reached cleanly
## (canonical decl-name tag; else a duplicate `__W` symbol).
run generic_structlit_dedup 42
check_accept repr_attr_parse
run repr_attr_parse 42
run variadic_sum 42
## a LEADING FIXED param before the `...` rest: accum(100, 10, 20, 12) = 100 + 10 + 20 + 12 = 142.
run variadic_accum 142
check_accept variadic_param_default
run variadic_param_default 42
## HETEROGENEOUS pack (§7.1): struct (multi-word) pack args — the loop var aliases each arg's type, so
## p.x/p.y resolve. span(a, b) over two Pt values = (10+5)+(20+7) = 42.
run variadic_struct 42
## CONTROL FLOW in the unrolled body: maxof(3, 42, 7, 20) with `if v > m { m = v }` per element = 42.
run variadic_max 42
## §7.2 SLICE variadic `xs : ...u64` — trailing args gathered into ONE runtime `[u64]` slice the body
## walks with `for x in xs`. Native scalar element, x86_64 (call-site gather is x86-only for now, so
## `run_x86` keeps it out of the sweeps — non-x86 backends are a follow-up). sum(10, 20, 12) = 42.
run_x86 slice_variadic 42
## §7.2 SLICE variadic WITH a leading fixed param `fn(base : u64, xs : ...u64)` — the fixed arg rides
## argreg(0), the gathered slice argreg(1). sumfrom(2, 10, 20, 10) seeds s=base then sums = 42. x86_64
## only (call-site gather is x86-only), so `run_x86` keeps it out of the non-x86 sweeps.
run_x86 slice_variadic_fixed 42
## §7.2 SLICE variadic with a FLOAT element `xs : ...f64` — the gathered args' f64 bits ride the slice;
## the param binds `eek == 9` so `for x in xs` yields a float loop var and the sum uses the xmm path.
## fsum(1.5, 2.5, 38.0) = 42.0 -> u64 = 42. x86_64 only (call-site gather is x86-only for now).
run_x86 slice_variadic_float 42
## §7.2 SLICE variadic with a STRUCT element `xs : ...Pt` — the gather lays `stride` words per element
## into a contiguous data block; the `...Pt` param binds `eek == 2` so `for p in xs` reads each element
## by reference. psum(Pt(10,11), Pt(20,1)) = 42. x86_64 only (call-site gather is x86-only for now).
run_x86 slice_variadic_struct_elem 42
## §7.2 SLICE variadic with an ENUM element `xs : ...Sh` — like the struct element, `stride` (1 + max
## payload) words per element; the `...Sh` param binds `eek == 3` so `for x in xs { match x }` reads
## each element by reference. esum(Sh.Sq(20), Sh.Tri(11)) = 42. x86_64 only (call-site gather).
run_x86 slice_variadic_enum_elem 42
## §7.2 SLICE variadic with MORE THAN SIX gathered args — the old `ng > 6` cap on the call-site gather
## was purely conservative and is now lifted (both the scalar and the aggregate gather loops are
## `ng`-general). SCALAR: sum of EIGHT u64 = 42. AGGREGATE: SEVEN struct elements (odd count) and EIGHT
## enum elements, each summing to 42. These use `run` (not `run_x86`) so the sweeps exercise them too:
## the call-site gather is x86-only, so on the non-x86 backends the slice-variadic call cleanly TRAPS
## (aarch64/riscv64 SIGTRAP, wat `unreachable`) — acceptable (a trap is never a silent miscompile).
run slice_variadic_scalar8 42
run slice_variadic_struct7 42
run slice_variadic_enum8 42
## §4 ABI / §8: multiple aggregate-value args in one call now get distinct agg-temp slices (was a silent
## alias miscompile). Flat (2 struct literals = 42) and nested (struct lit + struct-returning call = 42).
run multi_agg_arg 42
run nested_agg_arg 42
## §4/§8: runtime tuple element access t.N on a by-ref tuple PARAM (was a silent miscompile → 120).
run tuple_param 42
## §4/§8: MIXED-KIND tuple local (scalar then wider struct) — element N uses its own type+offset (was 36).
run tuple_mixed_kind 42
## §4/§8: MIXED-KIND tuple PARAM field access (by-ref dual) — t.1.x/.y resolve the struct component.
run tuple_param_mixed 42
## I11: match on an ENUM component that is NOT first (`match t.1`) — enum type from mixed-tuple tcomps.
run tuple_enum_later 42
## §4/§8: NESTED mixed-kind tuple element access (t.N.M) — component N's nested words read at its
## cumulative offset (was fail-loud). tuple_nested_index_legacy now COMPILES: t.0+t.1.0+t.1.1 = 40+1+1.
run tuple_nested_index_legacy 42
## I11 — the narrow-reservation slot collision behind the `emit_stmts` frame-layout lottery. `emit_gas`
## bound the name `tbc` twice: once as a `usize` scratch level and once as a 3-word struct. `:=` locals are
## function-scoped and the binders no-op on an already-bound name, so the struct inherited the ONE-word slot,
## stored over two neighbouring locals, and read `tbc.ok` from a slot NOTHING wrote — stale stack. When it
## came up non-zero, `array_of_tuples` exited 1 instead of 42 while `fixpoint.sh` and a tree-level `cmp` of
## the emitted GAS both stayed green, because `src/` has no array-of-tuple local to expose it.
build_reject_has reject_narrow_slot_rebind "already bound in this function by a NARROWER binding"
## §4/§8: NESTED mixed-kind tuple element access on a scalar-then-nested-tuple local: t.1.0/t.1.1.
run tuple_nested_index 42
## §4/§8: ONE-level TUPLE-element WRITE `t.N = v` (store dual of the tuple READ `t.N`) — overwrite t.1/t.2 of
## a flat scalar tuple LOCAL, the neighbour t.0 survives. Was a fail-loud "float literal" MISDIAGNOSIS. 10+99+12-79=42.
run tuple_elem_write 42
## §4/§8: NESTED mixed-kind tuple element WRITE `t.N.M = v` (store dual of the two-level read) — overwrite
## both words of a flat single-word tuple component; the scalar neighbour survives. 10 + 20 + 12 = 42.
run tuple_nested_write 42
## SOUNDNESS fail-loud: nested t.N.M where component N has a MULTI-WORD position (`(1,(100,200))`) — the
## flat single-word-position gate (tcomp ek==6) rejects it rather than truncating/mis-offsetting (was 120).
build_reject_has reject_nested_tuple_deep "nested mixed-kind tuple element access"
## SOUNDNESS fail-loud (WRITE dual): a nested tuple STORE `t.N.M = v` into a component with a MULTI-WORD
## position is rejected by the same ek==6 gate (falls through to emit_index_addr's guard), never mis-addressed.
build_reject_has reject_nested_tuple_write_deep "nested mixed-kind tuple element access"
## FN §5.1: NAMED call arguments — out-of-order diff(b=8, a=50) reorders to diff(50,8)=42; unknown name = fail-loud.
run named_args 42
build_reject_has reject_named_arg_unknown "named call argument does not match"
limit_scope_multi
## SYN-4: newline-as-separator for struct fields / call args / block statements (no comma/`;`).
run syn4_separators 42
run_x86 raw_asm_exit 42
run_x86 checked_overflow 132
run_x86 checked_routed_div_zero 132
run_x86 checked_routed_narrow 132
run_x86 checked_custom_routed_narrow 132
run_x86 unchecked_routed_add 42
## §4 built-in narrow-width WRAP on ALL FOUR backends. This one is a PLAIN `run`: the a64/rv64/wasm
## sweeps re-emit it and must agree on 54, so it verifies the non-x86 wrap (uN mod 2^N, iN signed
## range) end-to-end — `a+b`/`a*b`/`b-a` on `u8` truncated then division-lifted (see the test header).
run narrow_wrap_multiarch 54
## The `if x < 50` exit-code form of the same wrap; run_x86 (its 42/1 discrimination is x86-shaped —
## the plain-run multiarch coverage above is what exercises the three non-x86 backends).
run narrow_wrap_builtin 42
## Checked narrow-width overflow TRAPS (I11/CG-8): 200u8+100u8 > 255 → 132. run_x86 checks the exact
## trap exit here; the wrap/trap ARE emitted on all four backends (the sweeps accept a trap as exit
## >= 128 rather than asserting 132, so the precise trap code is pinned on x86_64 only).
run_x86 checked_narrow_ovf 132
run_x86 checked_narrow_shift_oob 132
## §8.1 `@require(pred) T` VALIDITY CONTRACTS: constructing a require-typed value via `T(v)` checks a
## comptime predicate and TRAPS (`ud2` → 132) when it is false — the checked mechanism, exactly like a
## narrowing overflow (§4.2). A SATISFYING construction runs (require_ok → 42); a VIOLATING one traps
## (require_trap → 132); an `unchecked` grant DROPS the check so a violating construction does NOT trap
## (require_unchecked → 42). Named f32/f64 predicates additionally lock the SSE `%xmm0` argument path
## (require_float_ok → 42; require_float_trap → 132). x86-only (the checked-predicate trap is emitted
## by the x86 back end).
run_x86 require_ok 42
run_x86 require_trap 132
run_x86 require_unchecked 42
## TYP-12 §8.1 — the AGGREGATE constructor gate. `R(v)` over a named plain struct evaluates `v` once,
## calls the predicate once through the ordinary by-value aggregate ABI, and delivers the value only on
## true; a false predicate is the CG-13 inline trap (132), never `panic`. `unchecked` drops the whole
## predicate path. `require_struct_ok` returns `hi - lo` = 10 by construction, not 42: it also proves the
## preserved value does not alias the predicate's temporary copy, and that the UFCS `Pair.require(p)` and
## prefix `@require(p) Pair` spellings agree. The frozen seed rejects these programs outright.
run_x86 require_struct_ok 10
run_x86 require_struct_trap 132
run_x86 require_struct_unchecked 42
run_x86 require_struct_wide 42
## TYP-12 §8.1 — ordinary tagged enum underlying type: checked construction copies the complete
## discriminant + two-word payload into a distinct predicate argument, preserves the result for an
## aggregate sink/return, and accepts both enum Vars and enum-returning calls as sources. The violating
## checked case traps directly; unchecked removes the entire predicate path. x86-only (ud2 is x86 ABI).
run_x86 require_enum_ok 42
run_x86 require_enum_trap 132
run_x86 require_enum_unchecked 42
build_reject_has reject_require_enum_union "ordinary tagged enum layout"
run_x86 require_float_ok 42
run_x86 require_float_trap 132
run_x86 require_ufcs_ok 42
run_x86 require_ufcs_trap 132
## An INLINE `@require(fn(v){…}) T` predicate is lifted to a synthetic function and checked at the
## explicit constructor site, just like the named form. A satisfying value runs; a violating value traps.
run_x86 require_inline_ok 42
run_x86 require_inline_trap 132
## A multi-token pointer underlying (`@require(pred) ptr(T)`) keeps the full type span for both the
## predicate ABI and the explicit constructor. Non-null passes through and a zero pointer traps.
run_x86 require_ptr_ok 42
run_x86 require_ptr_trap 132
## A raw union nested in a struct reserves its max member width with no discriminant. The following
## field must remain at the next word, while the union constructor writes its payload at offset zero.
run_x86 union_struct_field 12
## Types §9.4 first slice: typed uninitialized locals are accepted after a real write, aggregate slots use
## the declared width, and a read before the first write is rejected by checked sema.
run_x86 uninit_scalar 42
run_x86 uninit_immutable 42
run_x86 uninit_aggregate 9
run_x86 uninit_if_join 40
run_x86 uninit_if_diverge 1
check_reject reject_uninit_read
check_reject reject_uninit_if_partial
run_x86 uninit_field 42
run_x86 uninit_field_partial_ok 42
run_x86 uninit_nested_field 42
run_x86 uninit_nested_field_if_join 40
run_x86 uninit_nested_array_field 42
run_x86 uninit_nested_array_field_if_join 40
run_x86 array_field_nested_da 42
run_x86 array_field_nested_da_if_join 40
run_x86 da_array_field_nested_diverge 42
run_x86 uninit_array_struct_field 42
run_x86 uninit_array_struct_field_two 42
run_x86 uninit_array_struct_field_then_whole 42
run_x86 uninit_array_struct_field_if_join 40
run_x86 uninit_array_struct_field_if_diverge 42
run_x86 uninit_array_elem 42
run_x86 uninit_array_elem_if_join 40
check_reject reject_uninit_field
check_reject reject_uninit_field_whole
check_reject reject_uninit_nested_field_sibling
check_reject reject_uninit_nested_field_whole
check_reject reject_uninit_nested_array_field_sibling
check_reject reject_uninit_nested_array_field_whole
check_reject reject_uninit_nested_array_field_dynamic
check_reject reject_array_field_nested_da_sibling
check_reject reject_array_field_nested_da_other_index
## if/else-join read of a leaf written on ONE branch now correctly REJECTS again (743cf0d): the DA join-copy
## was silently dropping all field-level entries (root: a call().field codegen miscompile — see follow-up),
## so anything touched on either arm looked initialized. Fixed in sema; the join is now sound (both depth-1
## and deep). See da_reject_field_join / da_reject_deep_field_join / da_field_join_ok below.
check_reject da_reject_array_elem_nested_join
check_reject da_reject_array_elem_nested_sibling
## DA branch-merge is now sound: a leaf written on only one arm → reject (depth-1 and deep); all arms → accept.
check_reject da_reject_field_join
check_reject da_reject_deep_field_join
run da_field_join_ok 40
check_accept da_field_join_ok
## NOW SUPPORTED: the straight-line write `xs[0].inner.x = 42; return xs[0].inner.x` parses (ee76b5c) → 42.
run da_reject_array_elem_nested_unsupported 42
check_accept da_reject_array_elem_nested_unsupported
check_reject reject_uninit_array_struct_field_sibling
check_reject reject_uninit_array_struct_field_whole
check_reject reject_uninit_array_struct_field_partial_whole
check_reject reject_uninit_array_struct_field_dynamic
check_reject reject_uninit_array_struct_field_other_index
check_reject reject_uninit_array_struct_elem_whole
check_reject reject_uninit_array_struct_whole
check_reject reject_uninit_array_struct_elem_sibling
check_reject reject_uninit_array_struct_dynamic
check_reject reject_uninit_array_elem_sibling
check_reject reject_uninit_array_whole
check_reject reject_uninit_array_dynamic
run_x86 unchecked_narrow_shift_wrap 42
## Explicit overflow-policy operations (Concurrency §6.3 / CG-8): wrapping_*/saturating_*/checked_* (->
## Option)/overflowing_* (-> (T,bool)) on the integer interpretations, exercised at the u8/u64/i32
## boundaries. A NEUTRAL library addition (lib/base/num.al) resting on the x86_64-gated scalar
## operators, so run_x86 (sweep-excluded); returns 42 iff all 24 contract assertions hold.
run_x86 overflow_policy 42
## Checked narrow-width overflow TRAPS for an INDEX read (I11/CG-6): `xs[i]+xs[j]` on a `[u8;N]` array
## overflows u8 → 132. The element type is recovered from the array's declared `[u8;N]` so the index
## read classifies as narrow-width (was silently native-width → no trap). Companions: the non-overflowing
## narrow index add returns 42, and a native-width `[u64;N]` index add is unaffected (42). x86-only.
run_x86 checked_index_overflow 132
run checked_index_narrow_ok 42
run checked_index_native_ok 42
## CG-6 through an index-read BINDING: `x := xs[i]` on `[u8;N]` types `x` as `u8`, so a later
## `x + <literal>` (both operands non-index) is width-checked — 200+100 traps (132), 40+2 fits (42).
run_x86 checked_index_bind_ovf 132
run checked_index_bind_ok 42
## Signedness: an UNSIGNED ordering comparison (`u64`/`usize`) across 2^63 uses the UNSIGNED setcc
## (`setb`/…) instead of the always-signed `setl`/… fallback default — `0 < u64::MAX` is TRUE. A
## genuinely SIGNED `i64 -1 < 0` still uses the signed path. This x86 case ALSO asserts the signed
## path (the a64/rv64 fix is exercised by the plain-`run` unsigned_cmp_backends below) → run_x86.
run_x86 checked_unsigned_cmp 42
## Direct pointer-field signedness: `deref(p).u`/`.s` has declared integer type even though
## `expr_type_span` leaves the aggregate base unresolved; the lower bridge is exact to `deref(Var).field`.
run_x86 signedness_ptr_field 64
## Fixed-array by-reference parameter signedness: `a : [u64; N]` is an `is_ref` array slot, but its
## indexed element still has the declared builtin type. Keep the high-bit ordering unsigned instead of
## falling back to signed; unsupported Slice/variadic and non-variable bases remain unresolved.
run_x86 signedness_byref_array 42
## Indexed declared builtin-integer array FIELD signedness: `r.u[i]` recovers `[u64; N]`
## through the owning plain struct, so the high-bit boundary uses `setb` rather than `setl`.
## Global/variadic/aggregate and non-builtin field elements remain outside this bounded lane.
run_x86 signedness_struct_field_array 42
## Indexed module-global fixed-array signedness: recover the declared builtin element type from the
## global `: [T; N]` annotation (there is no local SlotEntry). High-bit u64 ordering must be unsigned;
## i64 division must remain signed. Inferred/aggregate/non-builtin/global-field forms stay conservative.
run_x86 signedness_global_array 42
## Same unsigned-across-2^63 fix on the a64 (`cset lo/hi/ls/hs`), rv64 (`sltu`) and wasm
## (`i64.lt_u`/…) backends: plain `run` so ALL sweeps exercise the boundary (a signed regression →
## non-42 = SILENT miscompile there). x86 also asserts 42; every operand is provably `u64` → UNSIGNED.
run unsigned_cmp_backends 42
## §4: `deref(p) = <struct literal>` stores all fields (was a silent 1-garbage-word scalar store).
run_x86 deref_assign_struct_lit 42
## FIELD write THROUGH a pointer `deref(p).field = v` (p : ptr(mut Rec)): the store dual of the
## `deref(p).f` read. Was a Priority-1 SILENT MISCOMPILE — `stmt_starts` did not recognize the shape, so
## the store parsed as a trailing return expr and was dropped (module could emit empty); lower's
## `field_slot` returned -1 for a Deref base → a store to `-0(%rbp)`. Writes word 0 + word 1 through the
## pointer param, reads back 40 + 2 = 42. x86-only (a64/rv64/wasm trap on the FieldPathAssign fallback).
run_x86 deref_field_write 42
run deref_subword_field_write 42
run_a64 deref_subword_field_write 133
run_rv64 deref_subword_field_write 133
run_wat deref_subword_field_write 134
run_x86 deref_subword_field_write_raw 42
run_ffi deref_subword_field_write 42
## MULTI-WORD struct FIELD write THROUGH a pointer from a struct-RETURNING CALL (`deref(p).i = mk()`) and
## an if-EXPRESSION with a CALL branch: the RHS aggregate materializes in the agg-temp, then all the
## field's words copy ASCENDING into (wfi+j)*8(ptr); both words land + the neighbour field is untouched.
## x86-only (the FieldPathAssign multi-word delivery is emitted on the x86 path). Exits 42.
run_x86 deref_field_agg_from_call 42
## MULTI-WORD struct FIELD write THROUGH a pointer from a LOCAL struct VAR (`deref(p).i = nv`): delivered
## INLINE in the FieldPathAssign arm (unrolled straight-line word stores — the compile-time copy loop
## lives in a pre-existing emit fn the seed lowers correctly, not the extracted helper the seed collapses
## to a single word). Both field words land + the neighbour field is untouched. x86-only. Exits 42.
run_x86 deref_field_struct_var 42
## MULTI-WORD struct FIELD write THROUGH a pointer from a BY-REF struct PARAM (`deref(o).i = v`, v : Inner
## passed by-ref = a pointer to the caller's Inner): the param pointer is loaded and word k read THROUGH it
## at k*8(vptr), then all words delivered (inline unroll). Both field words land + neighbour intact. Exits 42.
run_x86 deref_field_byref_param 42
## FIELD write THROUGH a POINTER FIELD `deref(node.next).field = v`: the write dual of the inline
## linked-list walk. Resolves the pointee through the field's pointer value. Same silent-no-op gap. 42.
run_x86 deref_ptrfield_write 42
## §4: `deref(p) = E.V(scalar payloads)` stores disc + payloads (was a silent 1-garbage-word store).
run_x86 deref_assign_enum_lit 42
# Checked div-by-zero traps on ALL backends (I11/CG-7): plain `run` so x86 asserts the exact
# SIGFPE exit (136) AND the a64/rv64/wasm sweeps assert a TRAP (exit >= 128), not a silent
# wrong low exit. `unchecked_div_zero` (aarch64-only, below) proves the guard is scoped away.
run checked_div_zero 132
## CG-13 — division by zero and `MIN / -1` are checked guards whose failure is the SAME direct inline
## trap as overflow (`ud2`, exit 132), emitted BEFORE the instruction. They used to reach the hardware
## `#DE` and exit 136, so one guard family had two observable failures.
run checked_udiv_zero 132
run checked_rem_zero 132
run checked_div_min_neg1 132
# Checked integer OVERFLOW on `+` traps on ALL backends (I11/CG-8): plain `run` so x86 asserts the
# exact SIGILL exit (132, `ud2`) AND the a64/rv64/wasm sweeps assert a TRAP (>= 128, brk/ebreak/
# unreachable), not a silent wrapped exit. `unchecked_add_ovf` (aarch64-only, below) proves scoping.
run checked_add_ovf 132
# Checked `*` overflow / `-` underflow trap on ALL backends (I11/CG-8): x86 exact 132 (ud2) +
# a64/rv64/wasm sweeps assert a trap (>=128). Companions below prove `unchecked` scoping.
run checked_mul_ovf 132
run checked_sub_ovf 132
## regalloc commit 4: a scalar-leaf TRAILING-VALUE checked `*` overflow goes through `emit_fn_ir`
## (register-allocated), not the text path — it must still emit the guard and TRAP (132). Locks in
## that the register allocator never drops a checked-overflow guard.
run ra_checked_trap 132
## regalloc CHECKED `/`/`%`: scalar-leaf division on the IR path. The positive case computes (a/b)+(a%b);
## the trap case divides by zero and MUST raise the hardware #DE → SIGFPE (exit 136 ≥ 128, an I11 trap).
run ra_checked_div 42
run_x86 ra_checked_div_trap 132
## regalloc bitwise `&`/`|`/`^` on the scalar-leaf IR path (opcodes and/or/xor): (a&b)|(a^b) == a|b
run ra_bitwise 42
run_x86 ra_const_fold 42
## Proposal #2 / scalar-IR fold-1: prove the immediate `&, |, ^` expression was folded before GAS,
## while the ALATYR_RA=0 escape hatch still computes the same answer through the old text path.
check_ra_const_fold
run_x86 ra_arith_const_fold 42
## Proposal #2 / scalar-IR fold-2: unchecked native scalar `+`, `-`, `*` immediate pairs fold to one
## `mov`, while `ra_selftest` separately locks the immediately-following checked overflow guard boundary.
check_ra_arith_const_fold
## Proposal #2 / scalar-IR fold-3: unchecked immediate logical shifts fold around the implicit `%rcx`
## count move; the ALATYR_RA=0 escape hatch still computes the same result through text lowering.
run_x86 ra_shift_const_fold 42
check_ra_shift_const_fold
## imm32 WIDENING: x86-64 encodes the immediate of `add`/`sub`/`imul`/`cmp`/`and`/`or`/`xor` in a 32-bit
## field that is SIGN-EXTENDED to 64 bits, so folding a wider literal into that operand made `as` REJECT the
## emitted text (`operand type mismatch for 'add'`, exit 13). The allocator now materializes such a literal
## into a register first. A check-only fixture would prove nothing here — the failure was the assembler — so
## this one ASSEMBLES, RUNS, and compares the register-allocated build against the `ALATYR_RA=0` text path,
## which never had the hole. Boundaries: `$2147483647` must STAY folded, and a `u64::MAX` mask must stay the
## folded `$-1` (it sign-extends from imm32), while `$2147483648` / `$4294967295` / `$4294967296` must not.
run_x86 ra_imm64_widen 42
check_ra_imm64_widen
## The widening must not displace a checked guard: the materializing move goes BEFORE the flag-producing
## instruction, so the `jcc`/`ud2` pair stays adjacent to it. 5 - 2^32 underflows u64 -> the CG-13 trap (132).
run_x86_trap ra_imm64_checked_trap 132
run_cli_trap ra_imm64_checked_trap 132
## regalloc bit shifts `shl`/`shr`/`sar` on the scalar-leaf IR path (opcodes 19/20/21, count in %cl via
## %rcx): shl(17,1)=34 + shr(17,1)=8 = 42, and sar(84,1)=42. Cross-backend MATCH (shifts already work in
## the text path); verified identical under ALATYR_RA=0 (text) = default (regalloc) on x86.
run ra_shift 42
## regalloc commit 5 (SysV CALLS + caller-saved clobbers): a scalar fn that CALLS other scalar fns is now
## register-allocated (`emit_fn_ir`). These lock in the CLOBBER SAFETY — a value LIVE ACROSS a call must
## NOT sit in a caller-saved reg (the callee would corrupt it); the allocator parks it in a callee-saved
## reg (prologue save/restore) or a spill slot. A dropped clobber = a silent miscompile = a wrong exit
## code. x86-only (the register allocator is x86 GAS; verified identical under ALATYR_RA=0 = text path).
run_x86 ra_call_live_across 42      ## value live across one call: 40 + add(1,1) = 42
run_x86 ra_call_two_calls 42        ## value live across TWO sequential calls: 36 + 4 + 2 = 42
run_x86 ra_call_arg_collide 69      ## value that is BOTH a call arg (%rdi) and live across the call
## regalloc commit 6 (the BARRIER bracket): a register-allocated fn contains ONE unmodeled construct — a
## SCALAR field read of a by-ref struct param — emitted through the TEXT emitter, bracketed by a full
## register clobber. A scalar LIVE ACROSS the barrier is forced to a spill slot (DISJOINT from the struct
## param's frame slot) and reloaded after. A lost/aliased scalar = a silent miscompile = a wrong exit code.
## x86-only (the barrier is x86 GAS; verified byte-answer-identical under ALATYR_RA=0 = pure text path).
run_x86 ra_barrier_field 42         ## t=10+20 live across `p.b`(=12) barrier: 30 + 12 = 42
run_x86 ra_barrier_two_fields 42    ## two barriers (p.a, p.b), two live-across scalars spilled: 27 + 15 = 42
# regalloc commit 6d (inline SCALAR ARRAY LOCAL iterated by `for x in ys`): the array-literal init routes
# through a STATEMENT barrier (text emit, full clobber) and the array stays FRAME-RESIDENT (its N words at
# the frame top, RA spill slots below), while the loop's accumulator + index stay REGISTER-resident across
# the loop (no per-iteration frame reload); the element base is a `leaq` (LEA-SLOT) + indexed `movq` load.
# Plain `run`: x86 asserts 42 register-allocated AND the sweeps assert the non-x86 text path never silently
# miscompiles. 10+20+3+9 = 42; verified byte-answer-identical under ALATYR_RA=0 (pure text path) on x86.
run ra_array_local 42
# Unsigned division of a high-bit u64: plain `run` so x86 asserts 63 AND the a64/rv64/wasm sweeps
# assert they now MATCH (was signed div on all three non-x86 backends — a silent miscompile).
run unsigned_div 63
# Integer width conversions on all four backends (§8; plain run so the sweeps validate the non-x86
# backends now COMPUTE them rather than trap-as-unsupported). u8 masks, i8 sign-extends.
run conv_narrow 42
run conv_signed 42
run_x86 checked_array_oob 132
run_x86 checked_agg_array_oob 132
run_x86 checked_global_arr_read_oob 132
run_x86 checked_global_arr_write_oob 132
run_x86 checked_struct_field_array_oob 132
run_x86 checked_byref_array_param_oob 132
run_x86 checked_slice_oob 132
run_x86 checked_str_oob 132
run_x86 raw_asm_add 42
run_x86 naked_add 42
run_x86 raw_asm_logic 42
run_x86 raw_asm_shift 42
run_x86 raw_asm_mul 42
run_x86 raw_asm_escape 42
run_x86 direct_jmp 42
check_x86_gas direct_jmp
fmt_test_has direct_jmp 42 "@label(done)"
build_reject_has reject_jmp_unknown "unbound name"
build_reject_has reject_jmp_duplicate "duplicate name"
build_reject_has reject_jmp_checked "invalid at line"
check_accept atomic_global_counter
check_accept ambient
check_accept check_typed_local
check_accept print_one
check_accept map_container
check_accept arch_intrinsic
check_accept for_over_slice
## generic-call type-argument parity (the §1 check/build gap): a generic call's `T : type` positions
## are type names, not values — the checker skips them POSITIONALLY (even a non-leading `T`), and a
## variant `match` arm binds its payload vars ARM-SCOPED so the body's references resolve.
check_accept generic_3param
check_accept option_map
check_accept higher_order_map
check_accept result_map
check_accept result_and_then
check_accept generic_enum_ret
check_accept generic_struct_param
check_accept match_multi_bind
run match_multi_bind 42
## comptime control-flow return-coverage (§1 check parity): a fn whose body is a returning
## `comptime if`/`comptime match` satisfies the missing-return check (the folded branch returns).
check_accept comptime_if
check_accept comptime_match_bare
check_accept comptime_enum_eq
check_accept comptime_variants
## bool-literal parity (the distinct BoolLit node): `true`/`false` type `bool`, so bool bindings/
## assigns/args/returns type-check — while `x : bool = 1` (a Num) stays a mismatch (reject_* below).
check_accept bool_literal
run bool_literal 42
check_accept display_enum
check_accept str_match
check_accept match_bool_neg
check_accept if_return_agg
check_accept enum_struct_payload
check_accept tuple_lit_arg
check_accept int_cmp_library
run check_typed_local 42
## §4 layout: a `str` field (2-word {ptr,len}) inside a struct local AND a mutable-global struct,
## with a scalar field after it (word-offset shift) — construction, read, and .data all correct.
run str_field_struct 42
## multi-word (str / 2-word pair) STRUCT FIELDS. `field_words` was already right — seven separate EMIT paths each
## still assumed one scalar word: a str field at a NON-ZERO offset used an ascending offset against descending
## slots; a str/pair field initialized from a non-literal stored NOTHING (`_ => {}`); a generic `v : T` was probed
## on the RAW span (and `struct_decl_of` missed the parenthesized head `Box(str)`); `c := b.v` read word 0 only;
## the same with a BY-REFERENCE base read the pointer slot as the struct (compiler SIGILL); and the field as a
## str VALUE pushed `$0,$0` (empty string). Pre-fix: 21 / 26 / SIGILL. a64/rv64/wasm trap.
run str_field_value 35
run str_field_eq 42
run gen_str_field 31
run slice_field_struct 30
## nested wide-SRET call arg `sumf(bump(mk(1)))`: the agg-value pool took a flat max instead of summing the
## nesting, so it aborted loudly. Now `own + deepest arg subtree`, mirroring a64's tree-wide count — all four
## backends MATCH (a64 already handled the nesting, which is what identified the fix).
run sret_nested_call_arg 18
check_accept str_field_struct
## §4 layout: an array field inside a mutable-global struct — element read/write + a scalar field
## after it (word-offset shift), with the array field laid out in .data as its element cells.
run global_struct_array_field 42
check_accept global_struct_array_field
## I11 / Types §9.4: a direct multi-dimensional fixed-array field currently has no composed nested
## address model. It must stop loudly for both a word-width and byte-width element, rather than let the
## second index fall through to slot 0 and return a clean wrong value.
build_reject_has reject_multidim_array_field_u64 "fixed-array field whose element is another fixed array"
build_reject_has reject_multidim_array_field_u8 "fixed-array field whose element is another fixed array"
check_reject_has reject_multidim_array_field_u64 "fixed-array field whose element is another fixed array"
check_reject_has reject_multidim_array_field_u8 "fixed-array field whose element is another fixed array"
## §4 layout: a str payload of an enum variant (2-word {ptr,len}) — construction, match binding
## (statement + expression), and s.len read; plus a sibling scalar-payload variant.
run enum_str_payload 42
check_accept enum_str_payload
## §4 layout: a str array [str; N] — indexed value read (str_eq) + xs[i].len (2-word element stride).
run str_array 42
check_accept str_array
## §4 layout: slicing a [str; N] LOCAL — arr[lo..hi] builds a typed Slice(str) (s.len, s[i], for-loop).
run slice_str_array_local 42
check_accept slice_str_array_local
## §4 layout: a nested enum payload (an enum variant whose payload is another enum) — recursive
## construction + nested match reads the inner enum's disc/payload.
run nested_enum_payload 42
check_accept nested_enum_payload
## `==` / `!=` over PAYLOAD-carrying enums (Option + a user enum) — link + compute correctly.
run enum_eq_payload 42
## RAW UNION (spec Types §6.3) — untagged overlapping-variant type. (1) round-trip: write a member,
## read it back → the value; (2) reinterpret + no-tag: write member `s` (i64 -1), read a DIFFERENT
## member `u` (u64) → the defined bit-reinterpretation u64::MAX (a discriminant word at offset 0 would
## return the tag instead); (3) size/align = the maxima, no tag word (union{a,b}=8 vs enum{a,b}=16);
## (4) a multi-word struct member at offset 0. Arch-portable (integer/layout only) → plain `run`.
run union_roundtrip 42
run union_reinterpret 42
run union_size 42
run union_struct_member 42
run union_copy 42
run union_global 42
## Nested generic enum payloads preserve their complete layout when constructed from literals, resolved
## CALLs, enum variables/parameters, and matched directly as a call result.
run nested_option_result 42
run nested_option_call 42
run codec_named_enum_call_payload 42
run codec_named_enum_bare_option_call 42
run codec_named_enum_literal_payload 42
run codec_nullary_enum_call_payload 42
run codec_nested_enum_forward 42
## §4: a const (non-mut) global array used as a lookup table (TAB[i]) — materialized in .data + indexed.
run const_global_array 42
check_accept const_global_array
## §4 layout: an array of tuples [(A,B); N] — tuple-element stride + nested xs[i].N component read.
run array_of_tuples 42
## §4 layout: a str field of an array-of-struct element (xs[i].key value + xs[i].key.len).
run array_struct_str_field 42
check_accept array_struct_str_field
## §4 layout — whole-AGGREGATE element WRITE to a LOCAL struct/enum-element array (`arr[i] = <agg>`). The
## local-array fallback stored ONE word → a Priority-1 silent miscompile (all fields past the first, and
## for a literal RHS even word 0, dropped). Lower now copies all `estride` element words: a struct LITERAL
## and a local struct/enum VAR RHS are delivered whole; a scalar FIELD write + the reads back them.
run arr_elem_agg_lit 42
check_accept arr_elem_agg_lit
run arr_elem_agg_var 42
check_accept arr_elem_agg_var
run arr_elem_agg_field 42
check_accept arr_elem_agg_field
run arr_elem_enum 42
check_accept arr_elem_enum
run arr_elem_agg_read 42
## WAT backend: aggregate-element arrays ([S; N], S a struct) — element field read, whole-element copy + write,
## across array local / range-slice view / global (.data at stride) / Slice(S) param. x86 and wasm MATCH; a64/rv64
## trap. (wasm sweep 134→142; a heterogeneous tuple literal now traps instead of yielding a wrong value.)
## aggregate ARRAY-ELEMENT access as a full matrix (read `xs[i].f`, whole-element copy, element assign from a
## literal and from a var, `xs[i].f = e`), on a LOCAL array-lit and on an array GLOBAL, at constant and runtime
## index. Three-field structs so every access lands on a distinct non-zero word offset, plus copy-independence
## and neighbour-untouched guards. Drove the rv64 backend from 146 → 156 sweep MATCH; a64/wasm still trap.
run agg_arr_elem_matrix 104
run global_agg_arr_elem_matrix 52
## a 4-word element struct (wider than the rest of the family) with a LOOP-driven runtime-index field read+write,
## plus copy-independence checks — and a lock for the SCANNER guard: two locals declared AFTER `ps[i].y = 40` /
## `ps[0] = P(…)`, which is exactly what breaks when a new Stmt kind is added to an emit path without walking
## every body scanner (both the rv64 and a64 lanes hit that). x86 = a64 = rv64 agree; wasm traps.
run arr_elem_field_loop_write 90
run arr_elem_local_after_ifassign 49
run agg_arr_elem_rw 119
run agg_arr_global_rw 71
run agg_arr_slice_elem 18
check_accept arr_elem_agg_read
## Deeper read seam: array element → intermediate STRUCT field → scalar leaf (`xs[i].inner.x`), combined
## offset locked non-zero by `pad`. Was a silent miscompile (deep read fell to `pushq $0` → 0). = 135.
run arr_elem_agg_deep_read 76
check_accept arr_elem_agg_deep_read
## Deep aggregate-through-INDIRECTION reads (were 4 silent miscompiles → 0 via composed offsets; x86; a64/rv64/wasm trap):
## xs[i].b.c.x (depth-3+ array-elem chain), deref(p).b.pb (depth≥2 thru ptr), a.b.pb off by-ref param, xs[i].arr[j] (index into array FIELD).
run deep_arr_elem_field 42
check_accept deep_arr_elem_field
## Types §9.4 — an array element, then a nested struct field, then an inline array field:
## `xs[i].cell.vals[j]`. The parser preserves the inner-index store and lower composes the element
## base with BOTH field offsets before applying the inner index. = 86; non-zero pads catch a dropped
## intermediate field offset. Unsupported aggregate forms remain fail-loud.
run deep_arr_field_elem 86
check_accept deep_arr_field_elem
run deep_arr_field_roots 14
check_accept deep_arr_field_roots
run deep_arr_field_inferred_local 25
run_a64 deep_arr_field_inferred_local 25
run_rv64 deep_arr_field_inferred_local 133
run_wat deep_arr_field_inferred_local 134
check_accept deep_arr_field_inferred_local
run reject_inferred_arr_field_agg_elem 0
run_a64 reject_inferred_arr_field_agg_elem 133
run_rv64 reject_inferred_arr_field_agg_elem 133
run_wat reject_inferred_arr_field_agg_elem 134
check_accept reject_inferred_arr_field_agg_elem
run reject_inferred_arr_field_agg_read 42
run_a64 reject_inferred_arr_field_agg_read 133
run_rv64 reject_inferred_arr_field_agg_read 133
run_wat reject_inferred_arr_field_agg_read 134
check_accept reject_inferred_arr_field_agg_read
## Issue #43 bounded slice: an inferred unannotated homogeneous word-granular local array now accepts
## `xs[i].arr[j] = P(...)` on AArch64; aggregate reads and unsupported backends remain fail-loud.
run deep_arr_field_inferred_local_agg_write 42
run_a64 deep_arr_field_inferred_local_agg_write 42
run_rv64 deep_arr_field_inferred_local_agg_write 133
run_wat deep_arr_field_inferred_local_agg_write 134
check_accept deep_arr_field_inferred_local_agg_write
run deep_arr_field_global 85
run_a64 deep_arr_field_global 85
check_accept deep_arr_field_global
run match_binding_root 119
check_accept match_binding_root
run match_binding_root_value 80
check_accept match_binding_root_value
run deep_arr_field_agg_elem 13
run_a64 deep_arr_field_agg_elem 13
check_accept deep_arr_field_agg_elem
run deref_nested_field 75
check_accept deref_nested_field
run byref_nested_field 75
check_accept byref_nested_field
run arr_field_elem_read 110
check_accept arr_field_elem_read
## write dual through a pointer: deref(p).b.pb = v then read.
run deref_nested_field_write 91
check_accept deref_nested_field_write
## deep array-element WRITE duals (straight-line), now parser-enabled (ee76b5c) → dormant lower branches:
## xs[i].a.b.c = v (FieldPathAssign) and xs[i].arr[j] = v (IndexAssign); a64/rv64/wasm trap. Neighbours intact.
run deep_arr_elem_field_write 80
## DEEP element addressing at a RUNTIME index on an UNINITIALIZED typed array local (`mut xs : [Row; 2]`, which
## is a Num(0) sentinel in the AST and used to reserve ONE frame word): xs[i].arr[j] read+write (indexing an
## inline [u64; 3] FIELD) and xs[i].inner.v read+write, both indices runtime, plus a local declared AFTER them
## (frame-scanner guard) and neighbour checks. This is what the a64 composed place-addressing lane delivered
## (7 TRAP→MATCH there); x86 = a64 = 98, rv64/wasm trap.
run deep_arr_elem_runtime_idx 98
check_accept deep_arr_elem_runtime_idx
check_accept deep_arr_elem_field_write
run arr_field_elem_write 116
check_accept arr_field_elem_write
## unary-minus as a binary operand `30 + -a` = 25 (was a SILENT 0: the SIGILL was masked by wexit) — the neg
## operand now forces the SIGNED overflow guard. a64/rv64/wasm trap (x86-only fix); 25 < 126 WASI-safe.
run lower_bugA_neg_operand 25
check_accept lower_bugA_neg_operand
## Types §9.4: a LOCAL struct with a `[Struct; N]` field — field_words now sizes it N*struct_words(elem) and the
## element stride is struct_words-aware. Construction, s.cells[i].m read + write round-trip, neighbours + pad/tail
## intact, whole-struct copy. 42 < 126 WASI-safe; a64/rv64/wasm trap (x86-only). (cfd5d39)
run struct_array_of_struct_field 42
check_accept struct_array_of_struct_field
## Issue #263 bounded x86_64 slice: direct struct-field arrays of plain narrow structs use the
## element's byte address and width for `s.items[1].a = value`; wide-field and local-array controls
## remain in the same focused fixture. The Slice(P), packed, pointer, generic, enum, global and
## non-x86 paths stay outside this registration.
run_x86 struct_field_array_narrow_write 42
## The LOCAL [Struct; N] field now works (above). The POINTER-COMPOUND `deref(p).cells[i].m` (a struct array
## field through a non-local root) stays a controlled panic — never a silent-0 / SIGILL — until the deep-nested
## resolver composes it. Workaround: bind the pointee to a local.
build_reject_has lower_bugB_array_of_struct_field "tuple/array element field not resolvable"
## Scalar array elements through a pointer-derived struct field are now supported; aggregate and
## deeper non-local forms above remain deliberate fail-loud fences.
run_x86 deref_array_field_place 42
check_accept deref_array_field_place
## Issue #220: AArch64 pointer-derived word-tier array-element field read/write at a runtime index;
## x86, RV64 and WAT retain their existing explicit fail-loud boundaries until their own slices land.
build_reject_has issue220_a64_deref_array_field "tuple/array element field not resolvable"
run_a64 issue220_a64_deref_array_field 42
run_rv64 issue220_a64_deref_array_field 133
run_wat issue220_a64_deref_array_field 134
check_accept issue220_a64_deref_array_field
## over-acceptance guard: a MULTI-WORD (struct-element) array-field leaf must fail loud, not silently read word 0.
build_reject_has reject_arr_field_agg_elem "xs[i].arr[j]"
## A struct-RETURNING CALL and an if/match-EXPRESSION (incl. a CALL branch) RHS into a local aggregate-
## element array are now delivered INLINE: the call/branch aggregate materializes in the agg-temp block,
## then all `estride` element words copy UP to the element base (both words survive). (A by-ref var / wide-
## SRET / tuple / generic-erased call RHS stays fail-loud — bind to a local first.)
run arr_elem_agg_from_call 42
check_accept arr_elem_agg_from_call
run ambient 42
run ambient_io 42
run ambient_io_result 42
## Appendix §160 — canonical alloc/base surface names: Vec::capacity/get, Option::get,
## and HashMap::insert/get, alongside the legacy implementation-prefixed names.
run stdlib_surface_aliases 84
run enum_agg_payload 42
run map_container 42
run vec_container 42
run fn_value 42
## FN-VALUE residual: a second wrapper forwards the same function value and two Slice views.
run fn_value_forward_lower_slice 42
## the supported way to call a fn value that isn't a bare name: bind it first (`g := fs[0]; g(10)`), plus HOF /
## returned-fn / equality / UFCS / lambda anchors — the forms the non-name-callee rejects must NOT disturb.
run fn_value_bound_callee 70
## FN-6 cross-backend seam: the driver-lifted non-capturing lambda is bound to a local name and called.
## The focused 10 result keeps this path independent from the larger x86-only fn-value fixture above.
run fn_value_local_lambda_cross 10
## Issue #7 bounded slice: a statement integer match must preserve the local result across the join.
run cross_match_local 42
## Issue #44 bounded WAT slice: scalar loop-expression break values survive the loop join.
run wat_loop_expr_value 42
## Issue #44 bounded WAT slice: scalar value breaks from nested loop/while/for bodies drain defers.
run wat_labeled_value_break 25
## Issue #44 bounded WAT slice: a statement-only labeled break exits a nested loop and drains both
## loop-body defers in LIFO order before the named-target branch.
run wat_labeled_break 21
## Issue #44 bounded WAT slice: a statement-only labeled continue drains nested and target-loop defers
## in LIFO order before routing to the outer loop's next-iteration edge.
run wat_labeled_continue 21
## Issue #44 bounded WAT slice: scalar value-loop labeled continue drains nested statement-only loops.
run wat_labeled_value_continue_defer 42
run_wat wat_labeled_value_continue_defer 42
## A named continue to the NEAREST value-bearing loop also has depth 0 in the AST. WAT must use the
## authored-label span to distinguish it from bare continue and route the named transfer to `$cont`.
run wat_labeled_value_continue 7
run_wat wat_labeled_value_continue 7
run_wat fn_value_local_lambda_cross 10
run_a64 fn_value_local_lambda_cross 10
run_rv64 fn_value_local_lambda_cross 10
## Два дефекта эмиссии, найденные тем, что 8 строк манифеста ушли из `run` в `assemble/1` — то есть
## задник начал выдавать текст, который ассемблер не берёт. Это не отказ и не ловушка: это испорченный
## вывод, и поймал его только манифест корпуса.
## (A) WAT: пояснение эмиттера писалось строчным комментарием `;;` ВНУТРИ s-выражения, а `;;` в WAT
## комментирует до конца строки — вместе с закрывающими скобками. Модуль оказывался разбалансирован, и
## следующая `(func …)` читалась как продолжение предыдущего тела. Все 57 пояснений переведены в блочную
## форму `(; … ;)`, потому что попадёт ли пояснение в середину строки, решает ВЫЗЫВАЮЩИЙ, а не само место.
## (B) a64/rv64: метка литерала с плавающей точкой — это начало его пролёта в исходнике, поэтому глубокое
## клонирование копировало её дословно, а обход rodata ходит по ОБЪЯВЛЕНИЯМ и писал ячейку по разу на
## каждое. x86 дедуплицировал давно; двум кросс-задникам добавлено то же множество.
run wat_hof_note_wellformed 42
check_accept wat_hof_note_wellformed
## Две разные величины, обе несущие результат: дедупликация «по клону» вместо «по смещению» дала бы здесь
## неверное значение, а не дублирующийся символ — то есть фикстура различает починку от её видимости.
run hof_float_pool_shared_cell 42
check_accept hof_float_pool_shared_cell
## FN-6 float ABI through a FUNCTION VALUE: an indirect call had NO return class and NO argument class (the
## parser keeps only the bare `fn` token, discarding the signature), so an `-> f64` result was read from %rax
## (silent 0) and float args went to GPRs. The class is now recovered by source-scanning the fn type. This also
## fixed the SHIPPED alloc::vec::map(f64, f64, …), which returned 244. Covers local/param, struct field, dyn pair.
## A `dyn` closure capturing an f64-TYPED value is fail-loud (the adapter moves env words through GPRs).
run fn_value_float_ret 42
run fn_value_float_binop 22
run fn_value_float_generic 12
run dyn_closure_float 15
## FN-6 — the AGGREGATE return class of an INDIRECT call (sibling of the float class above): an enum result
## rides disc/%rax + payload/%rdx and a struct rides %rax:%rdx:%rcx:… (>= 8 words: SRET), but the indirect call
## captured a single `pushq %rax` and never wired the hidden result pointer — `match f(x)` bound garbage (181)
## and a wide-struct fn value SEGFAULTED. Covers bare + annotated bindings, a fn-value param, a multi-field
## payload, and the 2-/7-/9-word struct returns. (12 silent miscompiles + 4 segfaults closed.)
run fn_value_enum_ret 42
run fn_value_struct_ret 42
## FN-10 — the same enum class through a fn-value STRUCT FIELD (`match o.g(x)`, silently 0 before).
## x86_64-only GAS (like fn_value_type) → run_x86.
run_x86 fn_field_enum_ret 42
run generic_fn_value 42
## FN-10 — the first-class function-value TYPE `fn(T…) -> R` (nameless params): bind a fn value to a
## typed binding + call it (indirect), pass it to a higher-order fn + call it, and STORE it in a struct
## field + call THROUGH the field. The struct-field indirect call is x86_64-only GAS, so run_x86.
run_x86 fn_value_type 42
## FN-10 — a call THROUGH a fn-VALUE STRUCT FIELD with NO same-named local in scope. `o.f(41)` desugars to the
## UFCS `Call(f, [o, 41])`, so its callee names neither a fn nor a local and `check` rejected the whole family
## with "unbound name". `fn_value_type` only LOOKED like it covered this: it holds a LOCAL named `op` that the
## local exemption resolved instead of the field. One arg / two args / a float signature / an aggregate argument.
run_x86 fn_field_call_nolocal 42
## FN-10 boundary — an AGGREGATE-returning field call BOUND to a local (`p := o.g(40)`) is resolved before the
## slot table exists, so it stays FAIL-LOUD (the exemption above is scalar-return only). Without this lock,
## widening the exemption silently turns the program into `return 0` (it did, mid-lane, and was caught).
build_reject reject_fn_field_agg_ret
## `check` used to ACCEPT this while `build` rejected it -- the fixture's own header says the shape "stays
## fail-loud in check", and it did not. Closing the UFCS parse-shape hole made check agree with build, so
## the located assertion goes beside the build one rather than replacing it.
check_located reject_fn_field_agg_ret 20
## FN-11 — a `dyn fn(…)->R` binding is constructed ONLY by `dyn_over(ptr(mut store))` (Functions §1.6). Binding
## it directly to a plain fn NAME has no env place: it used to SIGSEGV the COMPILER (139), now a located reject.
check_reject reject_dyn_fn_name
## FN-10 — a CAPTURING lambda coerced to a bare fn-value type has no home for its environment (a bare
## fn(…)->R is a one-word code pointer; capture needs `dyn`, FN-11): storing one in a fn-typed struct
## field MUST fail in semantic checking with a located diagnostic, before any backend emits code.
check_build_located reject_fn_value_capture 12 "type mismatch"
emit_reject_has wat reject_fn_value_capture "type mismatch"
emit_reject_has aarch64 reject_fn_value_capture "type mismatch"
emit_reject_has riscv64 reject_fn_value_capture "type mismatch"
## FN-11 — the type-erased `dyn fn(T…)->R` closure = a two-word {code, env} fat pair over EXPLICIT
## storage. Two DIFFERENT capturing closures (add-a / add-b) erased to one `dyn fn(u64)->u64` via
## `dyn_over(ptr(mut store))` and called through the fat pair (indirect, env passed leading). The inline
## per-lambda adapter + fat-pair call are x86_64-only GAS, so run_x86.
run_x86 dyn_closure 42
## FN-11 multi-capture — a `dyn fn(u64)->u64` over a lambda capturing TWO values (`x + a + b`); the
## adapter appends BOTH env words before the tail-jump. d(12) = 12 + 10 + 20 = 42.
run_x86 dyn_closure_multi 42
## FN-11 escape check (Memory §5.3.1) — a `dyn` value returned past its `store`'s scope must FAIL LOUD.
build_reject_has reject_dyn_escape "FN-11"
run deref_field 42
run deref_deref_field 42
run agg_call_arg 42
## §9.4 passing an aggregate ARRAY ELEMENT by reference as a call argument SEGFAULTED: emit_arg had no Index
## arm, so it fell to the general Index emitter, which computes the address correctly and then DEREFERENCES
## it -- handing the callee the element's first field VALUE as its by-reference block pointer. An aggregate
## element is a PLACE, not a scalar. All eight spellings faulted (constant and runtime index, 1-word and
## multi-word struct, enum, non-first argument, element of a by-ref param, element of a Slice(P) param).
run agg_arr_elem_arg 42
run_x86 issue260_slice_field 42
run_x86 issue261_slice_field 42
run_x86 issue263_slice_narrow_field_write 42
## CLAYOUT S4 (#263) — the CROSS-BACKEND half of the same defect: a struct-field array literal was
## materialized one machine WORD per field by aarch64/riscv64/wat, while every reader of
## `s.items[i].f` resolved it through the byte tier, so `s.items[1].a = v` destroyed `s.items[1].b`.
## Registered `run`, not `run_x86`, deliberately: the sweeps build their corpus from `^run [a-z]`, so a
## `run_x86` row is invisible to them — which is exactly why the three cross backends kept a silent
## wrong value here after the x86 fix landed. This fixture carries no local byte-tier array literal, so
## it stays clear of the wat construction fence and asserts a real 42 on all four backends.
run issue263_struct_field_array_neighbour 42
run generic_struct_inout 42
run ufcs_call_recv 42
run ufcs_call_args 42
run generic_struct_param 42
## generic-aggregate frontier: `deref(ptr(V))` store / param-store / load for a type-param `V`
## monomorphized to a multi-word struct (ek-7 via the instance Subst + pointee→pointee copy).
run generic_ptr_struct_deref 42
run nested_generic_struct 42
## TYP-10 slice A: a comptime VALUE parameter (`comptime N : u64`) on a type-function computing an
## array field's length (`[u64; N/64]`); `uint(192)` = 3 words, `uint(128)` a distinct 2-word type.
## generic-STRUCT-instance field access/construction (struct parallel of a118453).
run generic_struct_field 42
run struct_lit_agg_field 42
run uint192 42
## TYP-10 slice B: GENERIC OPERATORS over a comptime value param — one `@inline` `+`/`==` over
## `uint(N)` routes per operand base-head and expands per instance (`uint(192)` + `uint(128)` in
## one program), the ripple-carry `comptime for i in 0 .. N/64` bound folding against the bound N.
run uint_generic_op 42
## TYP-10 slice C: the SHIPPED generalized `uint(N)` recipe (lib/base/u128.al) at a THIRD width —
## `uint(256)` through the bare `uint(` ambient injection (no local decl): the full operator set
## (`+ - * / %` + the six comparisons), cross-word carry/borrow, a divisor with bits in a high
## word, and the `u128 ≡ uint(128)` alias interop (both names route the same generic `+`).
run uint256 42
run a64_large_frame 42
run_a64 a64_large_frame 42
## TYP-10 admissibility: `uint(0)` (non-positive) and `uint(100)` (not a multiple of 64) must FAIL
## LOUD at compile time — the comptime array-length fold (`ct_arr_len`) rejects both, never a
## silently-narrower type. Probed against the SHIPPED prelude via the bare `uint(` injection.
build_reject_has uint_bad0 "comptime array length must be POSITIVE"
build_reject_has uint_bad100 "inexact division in a comptime array-length expression"
## TYP-10 latent bug (exposed by the uint(N) work): a ONE-ELEMENT array literal as a struct-ctor
## field value (`S(words = [42])`, field `[u64; 1]`, wsize 1) fell to the scalar path and stored a
## SILENT 0 — the array-literal store was gated on `wsize > 1`.
run array_lit_single_elem 42
## TYP-10 latent bug (exposed by the uint(N) work): a generic-CONSTRUCTION-shaped literal
## `X(128)(words = […])` with an UNDECLARED head `X` compiled to a silent all-zero value instead of
## failing loud (the erased type-arg list left an unresolvable StructLit head).
check_reject_has reject_unknown_generic_ctor "unknown type constructor"
build_reject_has reject_unknown_generic_ctor "unknown type constructor"
emit_reject_has wat reject_unknown_generic_ctor "unknown type constructor"
emit_reject_has aarch64 reject_unknown_generic_ctor "unknown type constructor"
emit_reject_has riscv64 reject_unknown_generic_ctor "unknown type constructor"
run range_slice 42
run higher_order 42
run higher_order_map 42
run lambda_value 42
check_accept lambda_value
fmt_test lambda_value 42
run lambda_multiparam 42
check_accept lambda_multiparam
fmt_test lambda_multiparam 42
run lambda_two_same_arity 42
run lambda_capture 42
check_accept lambda_capture
run lambda_capture_multi 42
check_accept lambda_capture_multi
run lambda_capture_multistmt 42
check_accept lambda_capture_multistmt
run lambda_capture_struct 42
check_accept lambda_capture_struct
run closure_struct_capture 42
check_accept closure_struct_capture
run lambda_capture_call_result 42
check_accept lambda_capture_call_result
run lambda_capture_enum 42
check_accept lambda_capture_enum
run struct_array_param 42
check_accept struct_array_param
run lambda_capture_via_apply 42
check_accept lambda_capture_via_apply
run twice_capture 42
check_accept twice_capture
## FN-6 §6.2 — a CAPTURING closure through a HOF (`twice`) whose CLONED body carries a FLOAT LITERAL.
## The D-cap deep-clone copies the FloatLit's source-offset-keyed `.Lflt` label VERBATIM (no renumber
## field like a StrLit), so pre-fix the original + clone both emitted `.Lflt<off>:` → assembler
## "symbol already defined". `emit_rodata_expr` now dedups float `.rodata` by offset → assembles + runs.
run twice_capture_float 42
check_accept twice_capture_float
run twice_capture_generic 42
check_accept twice_capture_generic
run fold_capture_generic 42
check_accept fold_capture_generic
run twice_capture_multisite 42
check_accept twice_capture_multisite
run fold_capture_multisite 42
check_accept fold_capture_multisite
## FN-6 §6.2 — a CAPTURING closure through the REAL stdlib `alloc::vec::map` (a QUALIFIED cross-module
## generic `map(T,U,a,s,f)->Vec(U)`): module-aware qualified-callee resolution + a module-tagged clone
## whose body's bare `vec_in`/`push` still resolve in `alloc::vec` + `Vec(U)` sret under widened arity.
## x86_64-only (capture specialization is x86_64), so run_x86 (not swept).
run_x86 map_capture 42
check_accept map_capture
run lambda_capture_comptime_if 42
check_accept lambda_capture_comptime_if
check_accept lambda_two_same_arity
run slice_find_contains 21
run wide_struct_return 42
run sret_stack_arg 42
## wide-struct SRET where the returned value is a by-reference struct PARAM copied through the result pointer.
## Cross-backend: x86/a64/rv64/wasm all MATCH 45 (rv64 gained the LP64 indirect-result path).
run sret_param_fields 45
## SRET-temp wiring: a wide (>=8-word) return had no destination for the hidden result pointer in three shapes —
## tail-forwarding one SRET call out of another (was a SILENT 0), an SRET call in ARGUMENT position (was SIGSEGV),
## and returning a wide-struct PARAM by value (was a compiler SIGILL). All now correct; the emit_struct_to_sret
## catch-all is a controlled panic instead of a silent no-writer path. a64/rv64 trap, wasm matches.
run sret_tail_call_forward 21
run sret_call_arg 37
run sret_param_return 24
## a64 gained the x8 destination for a wide return in ARGUMENT + TAIL-FORWARD position (the arg case used to be
## a raw SIGSEGV 139, now a correct 37). Nested wide-SRET arg: x86/a64/wasm MATCH 37, rv64 traps.
run sret_call_arg_forward 37
## 9-word struct returned as a LITERAL (non-local return path); a64 SRET via x8 indirect result. = 15.
## Value kept < 126 so the WASM sweep's WASI proc_exit accepts it (150 would trap wasmtime → false miscompile).
run sret_lit_return 15
check_accept sret_lit_return
## a64 wide-SRET TRAILING-value delivery (fn body ends in a struct value, no explicit `return`) — was a clean
## a64 trap; now delivered via x8 indirect result (literal + local sub-paths). x86/wasm match, rv64 traps.
run sret_trailing_return 42
run sret_trailing_local 31
## SRET-DECISION family (both were silent 0): a GENERIC `-> T` wide return (the SRET call was decided on the
## declared span `T`, which resolves to no struct → bound as a bare scalar) and an explicit `return` of a WIDE
## ENUM (routing checked ret_enum before ret_sret; a wide enum has both). Boundary: 7 words register, 8+ SRET.
run gen_sret_wide_return 26
run_rv64 gen_sret_wide_return 26
## rv64 SRET call boundary: bare discard, eight-real-argument overflow after hidden a0, generic `-> T`,
## and a generic call receiving a nested wide-SRET aggregate argument.
run_rv64 rv64_sret_call_paths 67
## a generic type reference keeps only its HEAD in the AST (`Box`, with `(…)` left in src), and no seam ever
## handed a RESOLVED application span to subst_field_ty — so `Box(T)`'s field was sized as ONE word on both the
## callee's return and the caller's binding. With a struct type-arg the value read 0; with an ENUM type-arg the
## discriminant was garbage and a two-arm `match` ran NEITHER arm (the accumulator came back unchanged). Two
## independent holes in the same path were also closed: struct_has_nonstr_multiword_field tested the UNSTRIPPED
## span (false for every generic instance, even a fully concrete one), and emit_struct_value/emit_enum_value had
## no `Field` arm (`return b.v` fell to `movq $0`). a64/rv64/wasm trap.
run gen_struct_ret_agg_targ 42
run gen_struct_ret_enum_targ 42
run enum_sret_wide_var_return 36
run for_over_slice 42
# scalar range-slice READ on all four backends; WRITE on x86/a64/rv64 (wasm has no IndexAssign → traps)
run array_slice 42
run array_slice_struct 42
## BYTE-precise backend contract: raw mmap sentinels detect widened Slice/pointer stores.
run_x86 byte_precise 42
run_x86 fixed_array_byte_stride 42
run_x86 fixed_array_byte_layout 42
run_x86 fixed_array_byte_param 42
## String `\xHH` escapes decode before forming the `{ptr,len}` pair; invalid UTF-8 is rejected.
run_x86 string_xhh 42
run_x86 string_xhh_print 42
check_reject string_xhh_invalid
# Issue #321 / Stdlib appendix §3.6 + §8 — invalid raw str views must fail loudly; the
# corpus independently records the corresponding cross-target terminal trap rows.
run_x86_trap chariter_truncated_lead 132
## The invalid lead is a library validity failure (`panic`/exit 1), not the architecture's direct bounds trap.
run_x86 chariter_invalid_ff 1
run chariter_valid_utf8 42
## Variadic print must resolve indexed values and indexed call arguments to the same concrete
## `print_one__T` instance in the mono pre-pass and the emit pass.
run_x86 variadic_print_index 42
run slice_ptr_elem_deref 42
run slice_ptr_elem_write 42
run slice_ptr_elem_bound_local 42
build_reject_has slice_ptr_elem_deref_generic_reject "Slice(ptr(mut T))"
build_reject_has slice_ptr_elem_write_generic_reject "Slice(ptr(mut T))"
run slice_scalar_native 42
run slice_write_native 42
run float_native 4
run struct_enum_field 42
check_accept struct_enum_field
run struct_enum_value_match 42
run struct_enum_field_mutate 42
run struct_enum_field_return 42
run global_struct_enum_field 42
run match_struct_value 42
run field_agg_extract 42
run global_field_extract 42
run global_annotated_scalar 42
check_accept global_annotated_scalar
run global_annotated_struct 42
check_accept global_annotated_struct
run global_enum_field_write 42
run global_str_field_write 12
run global_nested_struct_read 42
check_accept global_nested_struct_read
run global_nested_struct_write 42
run global_nested_scalar_write 42
run global_deep_nested_read 42
check_accept global_deep_nested_read
run global_deep_nested_write 42
run global_nested_enum_match 42
run global_nested_str_len 42
run global_nested_substruct_write 42
run generic_struct_return 42
run generic_struct_ret_scalar 42
run generic_enum_return 42
## a NULLARY (zero-param) fn returning an enum, consumed by `match` — regression lock for the
## generic-resolution segfault where a nullary call whose name collides with a loaded generic
## (`get` vs `base/alloc`'s generic `get`) mis-resolved and crashed the compiler in mono collection.
run nullary_enum_return 42
## a DIRECT `return <EnumLit with a multi-word payload>` (`E.B(u64, u64)` / `E.B(u64, u64, u64)`) must
## deliver EVERY payload word — regression lock for a silent miscompile that dropped payload words 1..N.
run return_enum_lit_multiword 42
run array_struct_enum_field 42
run enum_match_field_place 42
run tuple_enum_component 42
run nested_enum_struct_enum 42
run enum_array_struct_payload 42
run_x86 issue254_enum_struct_field_array 42
build_reject_has issue254_pointer_probe "indexing a struct array FIELD through a non-local root"
build_reject_has issue254_packed_probe "matching an enum element of a packed/byte-layout struct array field"
run nested_tuple_bracket 42
run nested_tuple_dot 42
run array_enum_match 42
run for_over_array 42
run fixed_array_len 42
## Grammar §2/§3: newline is an array item separator, not only a source whitespace byte.
run array_literal_newline_separator 42
## Types §6.4 — `size([T; N])` ARRAY-TYPE literal as a comptime builtin argument (direct + UFCS,
## fill + comma form, scalar + declared-struct elements, `[T; 0]`/`[]` → 0): folds to `N × stride(T)`.
## Was an unbound-name check reject + a silent-wrong 8 for `[Rec; 2].size()`. Also the bare SCALAR
## type-name form `size(u64)`/`align(u64)` (a type arg, not an unbound value).
run size_array_type 42
run_x86 p1_bytes_zero_u8_local 42
check_build_located reject_p1_bytes_zero_u8_index 6 "invalid"
emit_reject_has wat reject_p1_bytes_zero_u8_index "invalid at line"
emit_reject_has aarch64 reject_p1_bytes_zero_u8_index "invalid at line"
emit_reject_has riscv64 reject_p1_bytes_zero_u8_index "invalid at line"
check_build_located reject_p1_bytes_zero_u8_index_assign 4 "invalid"
emit_reject_has wat reject_p1_bytes_zero_u8_index_assign "invalid at line"
emit_reject_has aarch64 reject_p1_bytes_zero_u8_index_assign "invalid at line"
emit_reject_has riscv64 reject_p1_bytes_zero_u8_index_assign "invalid at line"
check_build_located reject_p1_fixed_u64_index_assign 4 "invalid"
emit_reject_has wat reject_p1_fixed_u64_index_assign "invalid at line"
emit_reject_has aarch64 reject_p1_fixed_u64_index_assign "invalid at line"
emit_reject_has riscv64 reject_p1_fixed_u64_index_assign "invalid at line"
check_build_located reject_p1_struct_index_field_assign 5 "invalid"
emit_reject_has wat reject_p1_struct_index_field_assign "invalid at line"
emit_reject_has aarch64 reject_p1_struct_index_field_assign "invalid at line"
emit_reject_has riscv64 reject_p1_struct_index_field_assign "invalid at line"
## `alatyr run` reported a SIGNAL-terminated program as exit 0 (an unconditional WEXITSTATUS), so a trapping
## program looked like a clean success from the user-facing command. Covers SIGILL (132) and SIGFPE (136); a
## normal exit still reports its real status (every other `run …` line here proves that).
run_cli_trap checked_add_ovf 132
run_cli_trap checked_div_zero 132
run_cli_trap require_trap 132
run_cli_args cli_run_args 42
run_cli_args_sized issue346_args_65k 65000 c 42
run_cli_args_sized issue346_args_long 70000 x 42 tail
run_x86 os_arena_result 42
run size_type_arg 42
## Types §7 — a `[T]`/`str` VIEW is its two-word pointer+length pair wherever it appears, so `size(str)`,
## `str.size()` and `size(Slice(T))` are 16 on a 64-bit target and `size([str;2])` is 32. They used to answer
## 8 while a `str` FIELD already occupied 16 — the same wrong size that made the stdlib containers stride by
## one word. `size(Option(u64))` is 16 for the same reason; the `Option(ptr(T))` niche stays folded at 8.
run view_size_pair 42
## Grammar §130 line 287 / OP-2 — the EIGHT compound-assignment glyphs. Four of them (`%= &= |= ^=`)
## lexed as two tokens, matched no statement head, fell to the trailing-return-expression path, and the
## STORE WAS SILENTLY DROPPED with a clean compile: `x = 100; x &= 58` returned 100, and `check` exited 0
## (I11 — a wrong value is the only forbidden outcome). Beyond the four missing operators, every place
## form except a bare name and `name.field` required the plain `=` token in its lookahead, so ALL eight
## operators dropped their store on `a[i]`, `deref(p)`, `t.0`, `o.i.v` and `a[0].f`.
## `check_accept` matters as much as `run` here: the frozen seed COMPILED these programs, so a fixture
## that only ran would not show the shape of the defect — the compile was never the failure.
run compound_assign_silent_drop 42
check_accept compound_assign_silent_drop
## Eight operators on a name and on `name.field`, with operands 100 and 7 chosen so the results are
## PAIRWISE DISTINCT (107 93 700 14 2 4 103 99) — a substituted operator cannot pass another's check.
run compound_assign_bitwise 42
check_accept compound_assign_bitwise
run compound_assign_place 42
check_accept compound_assign_place
## x86_64-only BY MEASUREMENT, and not because of compound assignment: the fixture header records the
## plain-`=` control for each place, which traps on exactly the same backends. It adds 1 to each sweep's
## `trap` count, never to `wrong`.
run compound_assign_place_deep 42
check_accept compound_assign_place_deep
## The desugar reads the place by CLONING it, which is only equivalent for a re-readable place. A place
## holding a call (`a[f()] += 1`) would evaluate `f` twice where Memory §1 says once — measured: the
## textual rewrite calls `f` twice, and the seed called it once but dropped the store. So the whitelist
## rejects an unknown place shape rather than silently double-evaluating: a trap, not a wrong value.
build_reject_has reject_compound_place_call "compound assignment needs a re-readable place"
check_reject reject_compound_place_call
## `Stmt.Assign` does not distinguish a binding `x := v` from a store `x = v` — that fact is recovered by
## SCANNING THE SOURCE off the end of the name span, and there were THREE private copies of the scan listing
## 4, 5 and 4 of the eight glyphs. So `%= &= |= ^=` read as a FRESH binding: sema re-pushed the name as a new
## non-`mut` local, which rejected the next `=`/`+=` on it (a valid program refused) and ACCEPTED a compound
## write to an immutable binding; `fmt` re-emitted `x &= 58` as the declaration `x := x & 58`, rewriting the
## user's source. Now one predicate, `ast::compound_assign_op_at`, shared by every consumer.
## The seam is asserted in BOTH orders — new operator after old and old after new — because a fixture using
## only the new members passes while the seam is broken.
run compound_assign_reassign 42
check_accept compound_assign_reassign
## One file per operator, not one file with eight writes: the checker reports only the FIRST diagnostic, so a
## combined fixture would be rejected by its first line and prove nothing about the other seven. The
## dedicated diagnostic needle pins each reject to line 15.
build_reject_has reject_compound_immut_add "check: immutable binding at line 15"
check_reject reject_compound_immut_add
build_reject_has reject_compound_immut_sub "check: immutable binding at line 15"
check_reject reject_compound_immut_sub
build_reject_has reject_compound_immut_mul "check: immutable binding at line 15"
check_reject reject_compound_immut_mul
build_reject_has reject_compound_immut_div "check: immutable binding at line 15"
check_reject reject_compound_immut_div
build_reject_has reject_compound_immut_rem "check: immutable binding at line 15"
check_reject reject_compound_immut_rem
build_reject_has reject_compound_immut_and "check: immutable binding at line 15"
check_reject reject_compound_immut_and
build_reject_has reject_compound_immut_or "check: immutable binding at line 15"
check_reject reject_compound_immut_or
build_reject_has reject_compound_immut_xor "check: immutable binding at line 15"
check_reject reject_compound_immut_xor
## All eight spellings must survive verbatim, plus a bare `m - 50` that must NOT be read as `m -= 50`.
## The needles are checked against the fixture BODY: fmt preserves the header verbatim, so an explanatory
## header spelling out `f &= 58` would let every needle match its own documentation and pass unfixed.
run fmt_compound_assign_ops 42
check_accept fmt_compound_assign_ops
fmt_test_has_all fmt_compound_assign_ops 42 "a += 7" "a -= 7" "a *= 7" "a /= 7" "e %= 51" \
    "f &= 58" "g |= 51" "h ^= 51" "k &= 58" "m - 50" \
    "boundary512 += 1" "boundary513 += 1" \
    "long_add += 1" "long_sub -= 1" "long_mul *= 3" "long_div /= 2" \
    "long_rem %= 3" "long_and &= 3" "long_or |= 1" "long_xor ^= 3" \
    "plain343 = 2" "fresh343 := 5" "cmp343 == 2" "GMOD343 += 1" \
    "xs343 : [Row; 2]" "idle343 : u64"
## The FIELD place, which the bare-name lane deliberately left alone: `Stmt::FieldAssign` carried no
## compound-spelling probe at all, so `s.v &= 7` was re-emitted expanded as `s.v = s.v & 7` — for all eight
## glyphs, including the four that always parsed. Behaviour-identical (a `name.field` place has no side
## effect to re-run) but still a rewrite of what the author wrote. Operands 100 and 7 make the eight results
## pairwise distinct (107 93 700 14 2 4 103 99) and each is checked before the next, so a formatted program
## cannot hide a substituted operator behind the final value.
run fmt_compound_assign_field 42
check_accept fmt_compound_assign_field
fmt_test_has_all fmt_compound_assign_field 42 "a.v += 7" "b.v -= 7" "c.v *= 7" "d.v /= 7" \
    "e.v %= 7" "f.v &= 7" "g.v |= 7" "h.v ^= 7"
## A file whose token stream ends INSIDE an unclosed group is a located reject, not a silent accept. Every
## construct's terminator loop stops on the synthetic EOF as well as on its own closer (so a past-end peek
## cannot fault), which meant the loop waiting for `)`/`}`/`]` reached EOF, stopped as if the group had
## closed, and handed back a well-formed-looking decl: a truncated file BUILT and ran, and the mid-file case
## was quieter still — `check` returned 0 on a file whose `main` had vanished. `build_reject_has`, not a bare
## `build_reject`: the mid-file shape already exited non-zero before the fix, with a raw `ld` diagnostic
## about the missing symbol, so a non-zero exit proves nothing here.
build_reject_has reject_trunc_fn_params_body "ends inside an unclosed"
build_reject_has reject_trunc_fn_body "ends inside an unclosed"
build_reject_has reject_trunc_fn_params "ends inside an unclosed"
build_reject_has reject_trunc_struct_body "ends inside an unclosed"
build_reject_has reject_trunc_enum_body "ends inside an unclosed"
build_reject_has reject_trunc_midfile "ends inside an unclosed"
check_reject reject_trunc_fn_params_body
check_reject reject_trunc_midfile
## The other direction: the check must not OVER-reject. Both of these are legitimately unusual files that
## compiled before and must keep compiling — the residual-depth count is over tokens, so a brace inside a
## literal or a comment cannot perturb it.
run trailing_no_final_newline 42
run trailing_comment_no_newline 42
## The BALANCED truncation class — a construct whose continuation is mandatory ran out of input while the
## delimiters stayed balanced, so the residual-depth check above cannot see it. Enumerated over the grammar
## rather than guessed: 20 shapes, in both tail and mid-file position. Sixteen of them SEGV'd (rc 139, no
## message, no position) and they were ONE defect — `p_factor` matched no branch on the synthetic EOF token,
## fell through to its parenthesized-expression tail, stepped the cursor past the end and re-entered itself
## through `p_or` until the stack died. Four others were SILENT ACCEPTS: `f := fn`, `f := fn() ->`,
## `x := rt::` and `x := y.` each built with rc 0 and ran to 42, the truncated declaration simply vanishing —
## the forbidden outcome under I11, because the program that runs is not the program that was written.
## `build_reject_has`, never a bare `build_reject`: three quarters of these already exited non-zero (139 from
## the crash, or 14 from `ld` when a mid-file truncation ate `main`), so a non-zero exit proves nothing.
build_reject_has reject_trunc_bind_no_value        "input ends where a VALUE was required"
build_reject_has reject_trunc_binop_no_operand     "input ends where a VALUE was required"
build_reject_has reject_trunc_annot_no_value       "input ends where a VALUE was required"
build_reject_has reject_trunc_arrow_no_ret_type    "must be followed by a RETURN TYPE"
build_reject_has reject_trunc_fn_no_params         "must be followed by a PARAMETER LIST"
build_reject_has reject_trunc_fn_no_body           "must be followed by a braced BODY"
build_reject_has reject_trunc_path_no_segment      "must be followed by a path SEGMENT name"
build_reject_has reject_trunc_field_no_name        "must be followed by a FIELD, variant or tuple-element name"
## The mid-file variants are the quiet half of the class: the truncation ate the `main` that followed it, so
## the failure surfaced as `ld: undefined reference` with `check` returning 0 — indistinguishable from an
## empty file. `match` mid-file was the extreme: build 14, check 0.
build_reject_has reject_trunc_midfile_fn_no_body   "must be followed by a braced BODY"
build_reject_has reject_trunc_midfile_match_no_arms "must be followed by a braced arm list"
build_reject_has reject_trunc_midfile_if_no_branch "must be followed by a braced branch"
check_reject reject_trunc_bind_no_value
check_reject reject_trunc_arrow_no_ret_type
check_reject reject_trunc_midfile_fn_no_body
check_reject reject_trunc_midfile_match_no_arms
## The other direction, and it is not decoration: nine new guards in the parser are nine chances to reject a
## legitimate program. `x := rt::vec_len` (a module-member alias) and a named lambda both look like the
## truncated forms up to their last token and must keep compiling.
## An `if / else if / else` chain in VALUE position. `if_is_stmt_form` peeked for a statement head only
## inside the FIRST branch's body, so a chain whose first branch was a bare CALL and whose later branches
## were assignments fell through to "an `if` followed only by `}`/EOF is a tail value-if". `p_or` then read
## the statement branches as values and its blind `pc.idx + 1` skips stepped over the `=` signs, drifting
## the cursor out of the function — the error surfaced about fourteen lines later at the next top-level
## looking line, which is why one site in `src/lower/assign.al` was written as flag-guarded `if`s instead.
## Two of these shapes did not fail at all: they COMPILED CLEAN AND RETURNED THE WRONG VALUE (66 and 62
## where 42 is correct) — measured, not inferred, and an I11 violation this file had recorded as merely
## loud. Each fixture drives every arm of its chain with a distinct return code, so a misparse that takes
## the wrong branch cannot pass by arriving at the right final value.
run elseif_chain_tail_of_arm 42
run if_chain_nested_else_tail 42
run elseif_chain_value_form 42
## x86_64 only, and not because of the chain: a statement `match` over integer literals already traps on
## the three cross backends without any chain in it — confirmed identical on the base compiler.
run_x86 if_chain_tail_in_match_arm 42
## `build_reject_has`, not a bare `build_reject`: on the pre-fix compiler this fixture also failed, but for
## the WRONG reason (the desync), so a non-zero exit proved nothing about the diagnostic. The needle pins
## both the fault and its LINE — the chain here is a value-if whose branches produce no value, so the
## function that promises a `u64` does not deliver one, and the reject belongs at the construct.
build_reject_has reject_if_chain_tail_needs_value "check: invalid at line 7 in reject_if_chain_tail_needs_value"
run trunc_guard_portable_forms 42
run_x86 trunc_guard_signature_forms 42
run_x86 trunc_guard_bodyless_decls 42
## Every reject_* fixture used to record "accepted" in three of its four columns, and the binaries built
## from them ran to a normal exit under 128 on aarch64/riscv64 — a64_sweep's one forbidden verdict, which the
## sweeps cannot see because they iterate only the `^run ` lines below. 163 of 226 tracked reject fixtures
## flipped from "emitted with exit 0" to "rejected, nothing emitted" when the check pass landed; all 630 `run`
## fixtures still emit on all three surfaces, and every newly-rejected program was already rejected by
## `alatyr check`. Three surfaces per fixture, because one passing surface would hide the other two.
emit_reject_has wat     reject_emit_surface_type_mismatch  "alatyr: check: type mismatch at line 16 in reject_emit_surface_type_mismatch"
emit_reject_has aarch64 reject_emit_surface_type_mismatch  "alatyr: check: type mismatch at line 16 in reject_emit_surface_type_mismatch"
emit_reject_has riscv64 reject_emit_surface_type_mismatch  "alatyr: check: type mismatch at line 16 in reject_emit_surface_type_mismatch"
emit_reject_has wat     reject_emit_surface_unbound_name   "alatyr: check: unbound name at line 11 in reject_emit_surface_unbound_name"
emit_reject_has aarch64 reject_emit_surface_unbound_name   "alatyr: check: unbound name at line 11 in reject_emit_surface_unbound_name"
emit_reject_has riscv64 reject_emit_surface_unbound_name   "alatyr: check: unbound name at line 11 in reject_emit_surface_unbound_name"
emit_reject_has wat     reject_emit_surface_duplicate_name "alatyr: check: duplicate name at line 12 in reject_emit_surface_duplicate_name"
emit_reject_has aarch64 reject_emit_surface_duplicate_name "alatyr: check: duplicate name at line 12 in reject_emit_surface_duplicate_name"
emit_reject_has riscv64 reject_emit_surface_duplicate_name "alatyr: check: duplicate name at line 12 in reject_emit_surface_duplicate_name"
## `parser::parse_program` returns `Result(usize, ParseErr)`, and the LOCATION was never in that value —
## `ParseErr` is `Expected(u8)`/`Eof`, nothing more. The position lives in the `PC` the failed parse leaves
## behind, and `check_files` was the single caller that read it back. The other nine sites printed a bare
## `selfhost: parse error`: measured, `-o` and `fmt` were unlocated (the three emit surfaces only looked
## located because a check pass runs ahead of them). Proof the old text was one shared string for every
## source: both pre-existing parse fixtures hashed their stderr to sha256("selfhost: parse error"), and now
## each names its own file and line. The needle asserts the LOCATION, so a regression that keeps the reject
## and drops the position fails here — a bare `build_reject` could not tell the two apart.
## Note the exit codes differ BY PATH and that is pre-existing: 1 on build/fmt, 9 under check and the three
## emit surfaces. So `check_reject` (which demands 1) cannot be used on a parse fixture.
build_reject_has reject_parse_tail_located "at line 21 in reject_parse_tail_located"
build_reject_has reject_parse_located "at line 3 in reject_parse_located"
build_reject_has reject_parse_expected_assign "at line 7 in reject_parse_expected_assign"
## These four pass on the pre-fix compiler too — they are regression locks, not proofs of this fix (the
## three lines above are the ones that failed first). Registered because the emit surfaces are exactly where
## a future refactor would quietly drop the pre-pass and start emitting for an unparseable program.
emit_reject_has wat     reject_parse_tail_located "at line 21 in reject_parse_tail_located"
emit_reject_has aarch64 reject_parse_tail_located "at line 21 in reject_parse_tail_located"
emit_reject_has riscv64 reject_parse_tail_located "at line 21 in reject_parse_tail_located"
## CLAYOUT S3(a): a standard-byte-layout struct holding a nested aggregate field. `standard_byte_...` is
## the win (42 on all four backends; the base rejected on x86 and TRAPPED on the other three). The `packed`
## fixture is the gate for the regression the first attempt introduced — it read `o.inner.a` as `data[1]` on
## the three cross backends where the base was CORRECT, so a tier this slice does not claim got claimed.
run standard_byte_aggregate_field 42
run standard_byte_packed_root_nested 42
## The control: a word-layout struct passed by value must keep working, which is what caught an over-wide
## fence during the rework — the by-value param is not broken in general, only when the struct carries an
## aggregate field.
run word_layout_struct_by_value_control 42
## S3(b): the fence above these is GONE, and this is what replaced it. A nested child with a SUB-WORD field
## used to be built two different ways — x86's word constructor versus the cross backends' byte-precise
## recursion — so no single offset was right on all four and x86 answered 0 where the others answered 22.
## One shared byte-precise whole-value writer now serves all four: base was reject/133/133/134, and these
## are 42 on every backend. Bare `run` lines deliberately — that is what feeds the three cross sweeps, and
## a shape that works on x86 alone is exactly what this stage exists to stop shipping.
run standard_byte_subword_child 42
run standard_byte_subword_child_widths 42
run standard_byte_child_byte_array 42
## S3(c): the COPIER, and it is deliberately not a memcpy. One decision — `std_copy_kind` — answers for all
## four backends: copy the byte IMAGE verbatim when the destination is byte tier, or GATHER each scalar leaf
## from its §6.1 byte to its destination word (sign-extended per field width) when the destination is word
## tier. Word-granular children are not routed through it at all, which is why the GAS delta is empty rather
## than merely equivalent. Bare `run` lines — these feed the three cross sweeps.
run standard_byte_subword_child_copy 42
run standard_byte_whole_copy 42
run standard_byte_child_byte_array_copy 42
## S3(d): the byte-precise array-element tier now uses one stride oracle (`layout_elem_stride_bytes`,
## §6.4: size rounded up to align) and one domain predicate on all four backends. Every composed place
## still goes through S3(b)'s `layout_field_offset_bytes`; the two focused fixtures exercise dynamic outer
## indices, whole-element assignment, nested scalar fields, and a byte-array child without relying on stale
## artifacts.
## Bare `run` rows feed the three cross sweeps as well as x86, so a backend that regresses to the old
## wrong-value path is visible instead of being hidden behind the former emitter fence.
run_x86 standard_byte_array_elem 42
run_x86 standard_byte_array_elem_widths 42
run_x86 standard_byte_array_elem_copy 42
run_x86 standard_byte_array_elem_word_child 42
## The fixture that falsifies a WRONG STRIDE, and it exists because the value checks could not: with the
## stride mutated back to `estride * 8` (16 where 10 is right) every value comparison still returned 42 —
## 16 > 10, so nothing aliases and the writes and reads agree on the same wrong number. Only the ADDRESS
## falsifies it, so this one asserts `ptr(u[1]) - ptr(u[0]) == 10`, `size(Un) == 10`, `size([Un;3]) == 30`.
run_x86 standard_byte_array_elem_unaligned 42
## The word-granular control, portable, so it does feed the cross sweeps.
run standard_byte_array_elem_control 42
## New all-four seam fixtures: both are intentionally value-checked inside the program, with failure
## returns below 126. The former cross-backend reject fixture is now a positive regression row too: its
## word-granular nested child exercises the same byte-array-to-child offset seam.
run standard_byte_array_elem_dynamic 42
run standard_byte_array_elem_dynamic_control 42
run reject_standard_byte_array_elem_field 42
## Issue #170: direct scalar standard-byte struct arrays use the shared byte stride for both
## construction and indexed places on x86_64. AArch64/RISC-V already match; WAT remains explicitly
## fail-loud because its array-literal writer has not joined this slice yet.
run_x86 issue170_array_stride 42
run_a64 issue170_array_stride 42
run_rv64 issue170_array_stride 42
run_wat issue170_array_stride 134
## Issue #215: the bounded local [[u8;2];2] / [[u64;2];2] shape is rejected
## before emission because its nested lowering is not yet safe. Assert the same
## located diagnostic on check, x86 build, and every emit-to-stdout backend.
check_build_located issue215_local_multidim_array_u8 6 "local [[u8; 2]; 2] or [[u64; 2]; 2]"
emit_reject_has wat issue215_local_multidim_array_u8 "local [[u8; 2]; 2] or [[u64; 2]; 2]"
emit_reject_has aarch64 issue215_local_multidim_array_u8 "local [[u8; 2]; 2] or [[u64; 2]; 2]"
emit_reject_has riscv64 issue215_local_multidim_array_u8 "local [[u8; 2]; 2] or [[u64; 2]; 2]"
check_build_located issue215_local_multidim_array_u64 6 "local [[u8; 2]; 2] or [[u64; 2]; 2]"
emit_reject_has wat issue215_local_multidim_array_u64 "local [[u8; 2]; 2] or [[u64; 2]; 2]"
emit_reject_has aarch64 issue215_local_multidim_array_u64 "local [[u8; 2]; 2] or [[u64; 2]; 2]"
emit_reject_has riscv64 issue215_local_multidim_array_u64 "local [[u8; 2]; 2] or [[u64; 2]; 2]"
run issue215_local_array_1d_control 42
run_a64 issue215_local_array_1d_control 42
run_rv64 issue215_local_array_1d_control 42
run_wat issue215_local_array_1d_control 42
## Issue #324: direct nested fixed-array parameters are rejected before their corrupted ABI reaches a
## backend; the helper also keeps the existing x86 one-dimensional parameter control green.
issue324_nested_array_param_test
check_build_located reject_standard_byte_param 17 "check: invalid"
check_build_located reject_standard_byte_field_by_value 22 "check: invalid"
check_build_located reject_standard_byte_nested_field_addr 19 "check: invalid"
check_build_located reject_ptr_into_inner_field_write 21 "check: invalid"
## Wider than the byte tier and NOT a new defect: measured on the previous main, a plain WORD-layout
## `struct { pad : u64, inner : Inner }` reported `ptr(o.inner.x) == ptr(o.inner.y)` — one address for two
## distinct fields, exit 7 — and lost a store through `ptr(mut o.inner)` entirely, exit 20. Both were silent
## wrong values; `ptr(o.inner.x)` had fallen to `pushq $0` and the store went over the saved frame pointer.
check_build_located reject_word_layout_nested_field_addr 15 "check: invalid"
check_build_located reject_word_layout_ptr_field_write 20 "check: invalid"
## The six active S3(a) fences now reject identically through `check` and `build`, with a located diagnostic.
## The remaining historical S3(c/d) array-element rows stay build-only cross-backend fences and are kept
## separate above; their check/build parity is a later scope.
## CLAYOUT S2 — the two folds that were silently WRONG, and the guard that disagreed with them.
## `size((u64, u8))` answered 8: a mixed tuple was sized as if the u8 cost nothing, so standard product
## padding (u64 at 0, u8 at 8, tail to 8 = 16 bytes) was simply absent. And `when size(T) <= 2` did not
## share the layout tier `size(...)` uses, so a declaration guard and an expression disagreed about the
## same type. Measured on the frozen seed: both fixtures returned 1.
run tuple_mixed_size 42
run when_layout_tier 42
run_x86 when_size_boundary_24 42
## `size(Option(bool))` must REJECT until the real `@niche` lever lands (S6), not fold to the ordinary
## one-word fallback. Registered with the diagnostic needle, not a bare `build_reject`: on the pre-fix
## compiler this same fixture already failed — as "unbound name", an unrelated reason — so a plain
## reject assertion would have passed before the fix and proved nothing.
check_reject_has reject_option_bool_size "at line 4"
build_reject_has reject_option_bool_size "at line 4"
emit_reject_has wat reject_option_bool_size "at line 4"
emit_reject_has aarch64 reject_option_bool_size "at line 4"
emit_reject_has riscv64 reject_option_bool_size "at line 4"
run for_over_nonvar 42
run for_over_bytes 42
run for_over_struct_array 42
run match_comma_arms 42
run continue_stmt 42
## loop-as-expression `break <expr>` (§7.2) + labeled `break name` / `continue name` (§2.1/§7.1):
## a value-yielding loop, a break-value from inside a conditional, two same-type break exits, a labeled
## `break outer` exiting BOTH nested loops, and a labeled `continue top` re-iterating the outer while.
run loop_expr_labels 42
## §7.2 break-value TYPE CONSISTENCY (spec: "break-values of incompatible type are ill-formed"): the
## loop's type is the common type of its reachable break-with-value exits, so a KNOWN-incompatible pair
## (`break 1` + `break "abc"`; `break 1` + `break true`) is a located CHECK reject. Same-type exits and
## a bare `break` (diverging, no constraint) stay ACCEPTED. check-only reject/accept (the array-surface
## gaps stay separate); guard tests assert the check parity both ways.
check_reject reject_break_value_mixed
check_reject reject_break_value_int_bool
check_reject reject_break_value_var_mixed
check_reject reject_break_inferred_conflict_site
check_reject reject_break_inferred_conflict_nested_if
check_reject reject_break_inferred_conflict_nested_loop
build_reject reject_break_value_mixed
build_reject reject_break_value_int_bool
build_reject reject_break_value_var_mixed
build_reject_has reject_break_inferred_conflict_site "check: type mismatch at line 11"
build_reject_has reject_break_inferred_conflict_nested_if "check: type mismatch at line 14"
build_reject_has reject_break_inferred_conflict_nested_loop "check: type mismatch at line 13"
check_accept check_accept_break_value_same
check_accept check_accept_break_value_diverging
check_accept check_accept_break_value_var_same
check_reject reject_loop_expr_typed_sink_mismatch
build_reject_has reject_loop_expr_typed_sink_mismatch "check: type mismatch at line 3"
check_accept check_accept_loop_expr_typed_sink_same
## `break` inside a `for` (bare, in-a-conditional, labeled out of a for) + labeled `continue` out of a
## `for`. A bare `break` in a `for` had no real target (the `for` emit tracked only its continue label)
## → `jmp .L-1` (undefined) → link error; now the `for` pushes its done-label onto the loop-frame stack.
run for_break_labels 42
run match_bool_neg 42
run hex_literal 42
run tuple_return 42
## a >=8-component TUPLE return had NO sret path: components past the 7th came back from registers the callee
## never wrote (a SILENT garbage tail). Now the wide-struct hidden-result-pointer path. Boundary: 7 register, 8+ SRET.
run tuple_sret_wide_return 54
## a module-level global initialized by a runtime CALL returning an aggregate: the initializer never runs, so the
## value silently read 0. Const binding rejected; `mut` global FIELD READ rejected (the zeroed `mut` storage itself
## stays legal — the global-Mutex idiom in mutex_basic). A start-up-initializer phase is an open question.
build_reject_has reject_global_call_init "CONST module-level global initialized by a runtime CALL"
check_reject_has reject_global_call_init "CONST module-level global initialized by a runtime CALL"
emit_reject_has wat reject_global_call_init "CONST module-level global initialized by a runtime CALL"
emit_reject_has aarch64 reject_global_call_init "CONST module-level global initialized by a runtime CALL"
emit_reject_has riscv64 reject_global_call_init "CONST module-level global initialized by a runtime CALL"
build_reject_has reject_mut_global_call_init_field "reading a FIELD of a module-level global initialized by a runtime CALL"
p1_bytes_global_test
run call_bind_paren 42
run struct_return_1field 42
run return_match_agg 42
run if_return_agg 42
run nested_field_assign 42
check_build_located reject_nested_field_type_mismatch 7 "type mismatch"
run deep_field_agg_write 42
run deep_field_agg_if 42
run str_match_if_local 42
run agg_var_copy 42
run agg_from_branch_arg 42
run agg_from_branch_match_arg 42
run agg_from_branch_str_arg 42
run agg_from_branch_field 42
run struct_if_expr 42
run struct_if_expr2 42
run struct_match_field 42
run bitcast_agg2word 42
run bitcast_agg2word_unchecked 42
run issue369_aggregate_return 42
build_reject_has reject_issue371_packed_width "bitcast requires equal bit-width"
build_reject_has reject_issue371_packed_word_control "bitcast requires equal bit-width"
run_x86 accept_issue371_packed_equal_width 42
check_accept accept_issue371_packed_equal_width
run issue373_enum_bitcast_payload 42
check_accept issue373_enum_bitcast_payload
## Types §3.4/§4.4 — a PARENTHESIZED generic INSTANCE as the bitcast TARGET (`bitcast(Box(P), p)`).
## The target used to be erased whole, so the bound local kept no aggregate type and every field read
## ZERO; now the instance's own layout is reserved and its whole image moves. Each field is checked
## separately, so a partial or permuted copy names the word that moved wrong.
run issue372_generic_bitcast_target 42
check_accept issue372_generic_bitcast_target
## Types §§3.4/§4.4 and Memory §5.9 — an equal-width aggregate bitcast used DIRECTLY as a by-value
## struct ARGUMENT. The argument had no aggregate arm, so word 0 was passed as a VALUE and the callee
## dereferenced it as the block address: the reproducer died with 139 on x86_64. Each field is checked
## separately and every refusal code is distinct and based at 100, so a swapped or partly-copied image
## names the word that moved wrong. The unequal-width sibling must stay a located reject.
run issue370_bitcast_scalar_arg 42
check_accept issue370_bitcast_scalar_arg
build_reject_has reject_issue370_arg_width "bitcast requires equal bit-width"
run_x86 slice_field_compare 42
run qualified_value_arg 42
run cmp_prelude 42
run comptime_if 42
run unchecked_expr 42
run comptime_typeinfo 42
## CT: `comptime match typeinfo(T)` dispatch on the `Str` kind (appendix §4.1) — a `str` instance
## selects the `Str` arm, not the `Scalar` fall-through (Pointer/Function/Union also wired).
run typeinfo_kinds 42
run comptime_for 42
run comptime_variants 42
run comptime_enum_hash 42
run comptime_enum_eq 42
run agg_compare_fields 42
run nested_match_agg 42
run comptime_match 60
## CT §4.1/§4.2 — scalar type-name equality `T == <type>` + boolean and/or/not composition folded in a
## mono instance (40 for T==u64, 2 for not(T==u64) and verify.checked → 42).
run comptime_type_eq 42
## §3: a comptime-for over a numeric RANGE (comptime for i in lo..hi) — unrolled at compile time.
run comptime_for_range 42
check_accept comptime_for_range
## §3: a comptime-for range bound of typeinfo(T).n (comptime array length) — unrolls N times.
run comptime_for_typeinfo_n 42
## CT-6: the range bound uses the typeinfo(X) argument itself, even when X differs from the
## enclosing generic instance. The x86 lower is the authoritative field-derive implementation here.
run comptime_range_typeinfo_arg 42
run comptime_range_typeinfo_backend 42
build_reject reject_comptime_typeinfo_unknown_member
run_x86 comptime_typeinfo_field_mutable 42
## `comptime if` had a MUCH weaker evaluator than the `when`-guard path, and the gap was silent in two ways.
## (1) `!=` was never consulted in the arch fold, so `target.arch != Arch.x86_64` emitted the WRONG BRANCH —
## while sema and all three non-x86 backends already folded it correctly, i.e. they DISAGREED with the x86
## lower. (2) An unfoldable condition returned -1 and the CompIf emit then dropped BOTH arms with no
## diagnostic: `target.os`/`env`/`container`, a module const bool, a literal comparison, `size(u64) == 8`,
## `u64 == u64` and the spec's own arity-2 `resolves(f, a, b)` all silently deleted the branch. (3) `typeinfo(X)`
## ignored its ARGUMENT (the CompFor node drops it at parse time) and keyed off the mono instance type instead.
## Fixed by DELEGATING to the guard_* helpers plus a source-scan of the typeinfo argument — not a second
## evaluator. Anything still unfoldable is now a LOCATED reject (the lower had no diagnostic channel before).
run comptime_arch_ne 42
run comptime_target_facets 42
run comptime_if_facts 42
run comptime_typeinfo_arg 42
run comptime_resolves_args 42
## Comptime §9.1/§9.2 — every public entry point must reject a runtime-dependent comptime-if condition
## before emission, with the same located diagnostic and no output/artifact.
build_reject_has reject_codegen_comptime_cond 'codegen: `comptime if` — cannot fold this comptime condition. The lower folds target machine projections, verify.checked, build.<flag>, a module const, an integer comparison, size(T), typeinfo(T).fields/variants.len, a type equality, a `match typeinfo(T)` kind test, resolves(…)/compiles(…), and and/or/not over those. Rejected rather than silently emitting NEITHER branch. at line 8 in reject_codegen_comptime_cond'
issue297_codegen_multi_reject_test
check_reject_has reject_comptime_cond_unfoldable "comptime if condition must be comptime-known (runtime-dependent value) at line 11 in reject_comptime_cond_unfoldable"
build_reject_has reject_comptime_cond_unfoldable "comptime if condition must be comptime-known (runtime-dependent value) at line 11 in reject_comptime_cond_unfoldable"
emit_reject_has wat reject_comptime_cond_unfoldable "comptime if condition must be comptime-known (runtime-dependent value) at line 11 in reject_comptime_cond_unfoldable"
emit_reject_has aarch64 reject_comptime_cond_unfoldable "comptime if condition must be comptime-known (runtime-dependent value) at line 11 in reject_comptime_cond_unfoldable"
emit_reject_has riscv64 reject_comptime_cond_unfoldable "comptime if condition must be comptime-known (runtime-dependent value) at line 11 in reject_comptime_cond_unfoldable"
check_accept comptime_for_typeinfo_n
## §4: indexing a generic array param fn(T:type, a:T) with T=[E;N] — a[i] (runtime + comptime-unrolled).
run generic_array_param 42
check_accept generic_array_param
run effectors 42
run compound_assign 42
check_accept compound_assign
run compound_assign_ops 42
run arch_intrinsic 42
## x86_64 shift + bitwise intrinsics (shifts are call-form operations, not glyphs — spec OP-2).
run shift_intrinsics 42
check_accept shift_intrinsics
run shift_signed_infer 42
run overload_mangle 42
check_accept overload_mangle
check_build_located overload_ambiguous_located 7 "ambiguous call"
run overload_second_arg 42
check_accept overload_second_arg
run overload_three 42
check_accept overload_three
run overload_float_arg 42
check_accept overload_float_arg
run overload_scalar_agg 42
check_accept overload_scalar_agg
run ambient_strbuf 42
run ambient_alloc_into 42
run ambient_alloc_into_struct 42
run ambient_alloc_attr 42
run ambient_alloc_scalar 42
run ambient_alloc_deref_field 42
## issue #349 — `Arena.allocate` VALIDATES the requested alignment before the alignment
## arithmetic (Stdlib appendix §5.1 `BadAlignment`). Pre-fix, `align = 3` over a fresh arena
## returned `Ok(idx = 0)` (a misaligned success, exit 100 here) and `align = 0` reached
## `self.off % 0` and trapped instead of returning a `Result` at all. Covers 0/3/5/6/7 as
## invalid, 1/2/4/8 as still-valid, an untouched cursor after a rejection, and the unchanged
## `OutOfMemory` path. The fixture binds the `allocate` result through an EXPLICIT
## `Result(Handle(u8), AllocError)` annotation: `fmt` de-qualifies variant patterns (#393) and
## the bare names only resolve when the matched type is written in the source, so the inferred
## `r := allocate(…)` spelling fails fmt_corpus while staying fmt-idempotent. Do not
## "simplify" that annotation away without rerunning scripts/fmt_corpus.sh.
run issue349_arena_bad_alignment 42
## field read taken DIRECTLY off a pointer-returning call `f(x).field` — was a silent 0 (fell to pushq $0);
## now materializes the returned pointer then loads the field. Multi-word/unresolvable leaf fails loud. = 106.
run callfield_ptr_ret 106
## aggregate reached through a CALL RESULT — 3 silent-miscompile locks (each was 0/segfault, bind fixed it):
## chained field mk().b.c (=33), field off a generic struct-call id(P,x).b (=2), UFCS on a generic-enum call
## receiver find(1).unwrap() (=42). Multi-word/generic-payload receivers stay fail-loud. a64/rv64/wasm trap.
run callfield_chain 33
run callfield_generic 2
run ufcs_call_recv_unwrap 42
run ambient_vec_set 42
run vec_struct_field_update 42
run for_over_vec 42
## The view's whole-value load/store through a raw element pointer: `Vec(str)` used to move ONE word per
## element, so `at`/`get`/`split` returned empty or garbage-length strings with a null pointer — a SILENT
## wrong value in the shipped stdlib, not a crash. Elements have different lengths so a shared length cannot
## pass by accident, and content is verified through `bytes(...)`/`str_eq`, not just the length.
run vec_of_str_roundtrip 42
## S3(b) — the SAME dropped fact for every remaining container: `dq_elem`, `val_at`, `omap_val_elem` and
## `oset_elem` are declared `-> ptr(mut T)`, and at the use site nothing recovered `T`, so a `str` element's
## two-word pair was never materialized. Measured before: Deque read empty strings, HashMap returned the
## KEY in the length word (7 and 9), omap answered 192, and a second oset insert handed `less` a length of
## 755049445839631474 and SEGFAULTed inside `str_cmp`. The resolver matches the callee's returned pointee
## POSITIONALLY against its own parameters — never by name, which would be unsound across scopes.
run deque_of_str_roundtrip 42
run hashmap_str_value_roundtrip 42
run omap_str_value_roundtrip 42
run oset_of_str_roundtrip 42
run deref_view_pointee 42
## Types §7 — a `[T]`/`str` view IS its two-word {ptr,len} pair wherever it appears. A view ARGUMENT that is
## not a plain local (a struct FIELD at any depth, a `sub(…)`/range sub-view, a `[str;N]` element, a str field
## of an array-of-struct element, a mutable str GLOBAL) fell to the scalar path and passed ONE word:
## `io::print(p.name)` printed nothing and `io::print(sub(s,0,4))` SIGSEGV'd (the LENGTH went into %rdi as the
## block pointer). `emit_arg` had classified arguments by SHAPE, never by type. Content-checked via `str_eq`
## against literals of different lengths, each with a plain `str` local as the positive control. x86-only:
## `str` is entirely fail-loud on a64/rv64/wasm today, so these stay out of the swept corpus.
run_x86 str_field_call_arg 42
run_x86 sub_view_call_arg 42
run_x86 view_len_ptr_read 42
run arraysum_start 42
run for_over_slice_iter 42
run for_over_slice_struct 42
run bare_option_result 42
# `?` on a stdlib Option (`enum { None, Some(T) }`, Some=variant 1): the success branch must compare
# against the Some discriminant, NOT a hardcoded 0, so a following `Option.Some(<expr>)` delivers its
# OWN payload instead of leaking the `?`-unwrapped value. `use(41)` returns Some(v+1)=42.
run try_option_some_after 42
## DEFER (Control Flow §9.3 / Memory §5.8): cleanup runs LIFO on normal exit / before `return` / on the
## `?` early-exit; never on trap. LIFO(3,2,1) with ACC*4+n => 57; return-path => 8; ?-path => 1; normal => 10.
run defer_lifo 57
run defer_normal 10
run defer_return 8
run defer_try 3
run_wat defer_try 3
## DEFER BLOCK form (`defer { S1; S2 }`): both statements run TOGETHER as one LIFO unit, in order.
run defer_block 12
run_wat defer_block 12
## Two `defer { }` blocks run LIFO (last registered first) as separate units.
run defer_block_lifo 21
run_wat defer_block_lifo 21
## A `defer { }` whose body declares a LOCAL + uses a STRING LITERAL (block stmts are still ordinary
## statements to the slot-collector and `.rodata` walker): ACC = len("hello") = 5.
run defer_block_local 5
## A `defer` in a `loop` body runs on `break` (per-iteration body-frame drain before the jump).
run defer_loop_break 111
## A `defer` in a `while` body runs on `continue` (per-iteration), re-registered each pass.
run defer_loop_continue 111
## A `defer` inside an `if { }` arm is scoped to the ARM — it runs at the arm's fall-through.
run defer_nested_block 12
## fn-body defer + nested-block defer: on `return` the NESTED (inner) runs first (LIFO across scopes).
run defer_nested_lifo 12
## §9.3 defer semantics locked at the two points that are easy to get subtly wrong, and that the WAT backend
## needed spelled out when it gained defer (7 traps → MATCH): the action is evaluated at DRAIN time, not at
## registration (a captured local must read its value at exit), a loop body drains PER ITERATION, and the exit
## VALUE is computed before the drain runs. Each defect yields a distinct number (41/32/31 and 58/3).
run defer_drain_time 95
run defer_value_order 44
## A `defer` in a VALUE-BEARING `loop` (`x := loop { … break 5 }`): the break value and the drain coexist
## (value pushed, drain sits above it, done-label converges with exactly one value).
run defer_value_loop 16
run_wat defer_value_loop 16
## DEFER BLOCK FAIL-LOUD: a `defer { }` may not contain control flow (`return`/`break`/`continue`/`?`) —
## a jump out of a cleanup would skip the rest of it / jump into stale labels (partial-cleanup hazard).
build_reject_has defer_blk_reject "defer — a"
# §8 @niche: Option(ptr(T)) is a niche-folded enum (pointer-width, None=null, Some(p)=p). Folds the
# discriminant word — x86_64-only lower path, so run_x86 (excluded from the arch sweeps' `^run ` grep).
run_x86 niche_option_ptr 42
run_x86 option_ptr_helpers 42
run_x86 niche_option_return 42
run_x86 niche_option_field 42
run_x86 niche_option_str_match 42
run alloc_with_elision 42
## MEM-5 nested lexical allocator scope: omitted `with_capacity` follows inner ambient, then restores
## outer ambient; an explicit `ptr(outer)` remains explicit even inside the nested scope.
run ambient_alloc_nested_shadow 42
run alias_injection 42
run ufcs_push_local 42
run ambient_hashmap 42
## Comptime §3.3 — a comptime type argument INFERRED from a `str` view argument, and the fail-loud reject
## when no rule can infer it. A view slot records the view KIND, never a type SPAN, so inference failed and
## the call did NOT stop: it took the first VALUE argument for the erased type argument and passed nothing —
## `println(s)` printed `0`. Same dropped fact made `alloc::hashmap::rehash` hash a garbage register once a
## map outgrew 8 buckets (`hash(k)` with an un-inferable `K`), which no fixture had ever reached.
run_x86 generic_view_targ_infer 42
run_x86 hashmap_rehash_grow 42
## Stdlib §6 / §2.6 — a `str` KEY: `HashMap(str, V)` was REJECTED outright. `typeinfo(str)` is the
## opaque §4.1 `Str` kind, for which the structural `hash(T, v)` had no arm — it fell through to
## `u64(v)`, which refuses a two-word view — and inside the instance the key PARAMETER carries no
## readable `str` annotation, so `hash(key)` / `eq(existing, key)` inferred no comptime type argument
## either (Comptime §3.3 reject). Two equal-content views in SEPARATE mmap allocations, so a
## `{ptr,len}` hash or equality cannot pass; the 7th insert forces the rehash, whose `hash(K, k)` is
## the explicit spelling and must agree with `insert`'s implicit one.
run_x86 hashmap_str_key 42
run ambient_hashmap_struct 42
## NESTED-aggregate structural eq through the derive: a nested field must compare ALL its words, not
## word 0 only (the derive recurses explicitly `eq(f.type, …)`, so a struct-in-struct key is exact).
run hashmap_nested_key 42
## std::random — splitmix64 PRNG: determinism (same seed → same stream) + range + state advance
run random_prng 42
## std::time — clock_gettime(2): monotonic non-decreasing + realtime-after-epoch + to_nanos conversion.
run std_time 42
## std::math — pure-Alatyr f64 fns: sqrt (Newton), abs, fmin/fmax, floor/ceil/trunc (incl. neg floor).
run std_math 42
run std_math_more 42
## std::math transcendentals — each in its own program (exp/ln/sin/cos + sqrt), one deep-float fn per
## build to stay under the frozen seed's compile-time emit-scratch ceiling (several together OOM emit).
run math_exp 42
run math_ln 42
run math_sin 42
run math_cos 42
run math_sqrt 42
## std::path — POSIX lexical decomposition (allocation-free str views): basename/dirname/extension/
## stem/is_absolute across trailing-slash, dotless, and leading-dot cases.
run std_path 42
run ambient_string 42
## #355 alloc::string::push / push_str report the NEW byte length (Stdlib appendix §6: a fallible
## mutator with no natural result carries a usize count in its Ok arm — the new length), not the
## number of bytes appended. Both forwarded alloc::strbuf, whose writers report what they wrote.
## Rows cover repeated appends, an EMPTY push_str (unchanged length, not 0), the 1/2/3/4-byte UTF-8
## char widths, a growth across a reallocation, and a char as the first append.
run issue355_string_push_len 42
## alloc::vec accessors: at (bounds-checked Option read), first/last, swap_remove (O(1) unordered).
run vec_access 42
## #354 alloc::vec::reserve is fallible: a request that cannot be represented in `usize` returns
## Err(SizeTooLarge) instead of trapping (each of `len + additional`, the capacity doubling, and
## `new_cap * size(T)` was a bare checked operator and aborted with SIGILL). The no-op, ordinary
## growth, post-refusal-still-usable, and representable OutOfMemory rows are the controls.
run issue354_vec_reserve_overflow 42
## alloc::deque — a double-ended queue (ring buffer): push/pop both ends, wrap-around, growth (cap 2
## → forced doubling + re-linearize), front/back/dq_at reads.
run deque_ops 42
## alloc::oset — an ordered set (sorted array): insert keeps it sorted + duplicate-free via a caller
## `less` comparator (binary search + tail byte-shift, growth), contains (O(log n)), sorted as_slice.
run oset_ops 42
run omap_ops 42
## alloc::omap with a MULTI-WORD STRUCT value type — insert out of key order (shifts + two grows) +
## overwrite, then read every field back through the `omap_values` slice. Guards the generic-aggregate
## `deref(ptr(V))` element store/shift (`deref(vd) = deref(vs)` / `deref(vslot) = value` with V a struct).
run omap_struct_value 42
## A generic enum-INSTANCE whose type-param monomorphizes to a MULTI-WORD STRUCT delivers the WHOLE
## payload through construction + return-register + match-binding: `Option(V)`/`Result(V, _)` with V a
## 2-word struct (from a by-ref struct param). Formerly truncated word 1 (same-fn bind) / crashed the
## compiler (checked slot-offset underflow reading a by-ref struct-param payload).
run generic_enum_struct_payload 42
## std::serialize — little-endian binary encode/decode over an arena: put/get for u8..u64, i8..i64,
## bool, f64 (bit-identical), and length-prefixed byte/str blobs through a bounds-checked Reader cursor.
run serialize_roundtrip 42
run enum_struct_payload 42
run enum_dot_match 42
run slice_param 42
run slice_struct_param 42
run slice_struct_local_arg 42
run slice_enum_param 42
## the .len FIELD (vs the .len() method) on a slice PARAM: must double-deref the caller's {ptr,len}
## block (was reading a garbage slot word). Scalar + str element.
run slice_len_field 42
## a str-ELEMENT Slice(str): the element binds eek 4 / stride 2, so a whole-value read (e := parts[i])
## and a field read (e.len) both deliver the full {ptr,len} pair (was a silent word-1 drop). Built over
## a raw mmap page (the up-growing shape std::os::args yields).
run slice_str_read 42
## a typed array-slice bound to a LOCAL (s := arr[lo..hi]) then passed as an ARG — must hand the callee
## the local's ADDRESS (block pointer), not word 0 (data ptr); else s.len read a garbage len. Scalar + str.
run slice_local_arg 42
## alloc::string::join over a Slice(str) — the str-element whole-value read inside a loop (bound to a
## local, passed to push_str), driven by `parts.len()` (the METHOD; `.len` field on a slice param is a
## separate, now-fixed miscompile). Verifies the joined result via as_str.
run str_join 42
run shift_ops 42
run bitwise_not 42
## narrow-width `~` masks to the operand width (`~213u8` = 42, not 0xFF…2A). x86-only (narrow arith).
## narrow `~` masking (the `x^(-1)` desugar → mask to operand width) on all four backends.
run narrow_bitnot 42
run linked_deref 42
run linked_walk 42
run deref_field_direct 42
run nested_enum_copy 42
run capture_array 42
run ambient_push_loop 42
run ambient_strmap 42
run comptime_match_bare 42
run implicit_typearg 42
run match_call_bind 42
run display_render 42
run display_nested 42
run display_brand 42
run display_brand_float 42
run display_enum 42
run display_generic_enum 42
run display_result 42
run display_tuple 42
run tuple_lit_arg 42
run tuple_mixed_value 42
run display_array 42
run display_nested_agg 42
run display_array_struct 42
run display_tuple_agg 42
run display_enum_multi 42
run println_enum 42
run print_one 42
run variadic_print 42
## §5 bare-prelude: a bare `print`/`println(...)` call injects std/fmt (the qualified form was
## already reachable) — closes the §3/§5 acceptance form `print("value = {}\n", 42)`.
run bare_prelude_print 42
run print_literal_hole 42
run print_str_hole 42
## I11 stdout golden over the three reported silent `str`-argument repros in STATEMENT position, where the
## failure left no trace at all: a view FIELD, a `sub(…)`/range/array-element view, and `println(s)`.
run_x86_out view_arg_print_out 42
run print_float_hole 42
run print_escape 42
run str_match 42
## base/str `trim`/`trim_start`/`trim_end` (ASCII-ws trimming → a str VIEW, no allocation) reached via
## the ambient `base::` root (a user program pulls `lib/base/str.al` by a `base::str::…` / `strm :=
## base::str` reference — the third lib tier alongside `alloc::`/`std::`).
run str_trim 42
## base/str trim_matches / trim_start_matches / trim_end_matches: strip a specific byte (views).
run str_trim_matches 42
## base/str ASCII case folding (allocation-free, byte-level): eq_ignore_ascii_case + to_ascii_lower/
## upper + the is_ascii_* classifiers, via the base:: root.
run str_case 42
## base/str search + parse, now `pub` (were defined but unreachable): starts_with/ends_with/contains_str/
## count_str/find_str/index_of/parse_uint/parse_int/str_cmp, via the base:: root.
run str_search 42
## base/str right-to-left search: rindex_of (last byte) + rfind_str (last substring).
run str_rsearch 42
## base/str strip_prefix/strip_suffix (str views): peel a known lead/tail if present, else unchanged.
run str_strip 42
## base/str byte helpers: count_byte + common_prefix_len (allocation-free).
run str_byte_ops 42
## base/char classification + folding, now pub: is_digit/is_alpha/is_alnum/is_whitespace/is_hex_digit,
## to_lower/to_upper (ASCII), hex_value (Option(u32)), via the base:: root.
run char_class 42
## base/slice READ-ONLY functional toolkit (len/reduce/count_if/any/all/contains/find/first/last, fn-value
## predicates) + base/cmp min/max/clamp — now pub. Slices passed directly (arr[0..N]).
run slice_toolkit 42
## a GENERIC index WRITE s[i]=x on a Slice(T) param — the element T is now substituted at bind so the
## param binds by-ref (was is_ref=false → the write overwrote the slot / a read returned the block ptr).
run slice_generic_write 42
run_rv64 slice_generic_write 42
## Issue #213 residual: RV64/Linux same-module monomorphized Slice(u32) parameter write. The fixture
## checks the write, neighbouring elements, and read-after-write; its row-private control checks OOB.
run_rv64 slice_generic_u32_write 42
issue213_rv64_slice_controls_test
## The AArch64 generic Slice(T) write path is also used transitively by base::slice::sort's sift_down.
run_a64 slice_generic_write 42
## §7.2: a fn RETURNING Slice(T) by value — was a silent miscompile (bound as a bare scalar → .len read 0, [i]
## garbage; bind did NOT fix it). Now binds an ek-5 {ptr,len} slice; direct `.len`/`.ptr` read %rdx/%rax, direct
## `f(…)[i]` fails loud (bind first). a64/rv64/wasm trap. = 42.
run slice_return_byvalue 42
## `.len`/`.ptr` taken DIRECTLY on a str-returning CALL was 0 in every operand position while the bound form
## `s := rd(); s.len` was right — the two spellings disagreed. (The Slice-returning-call case was already handled;
## this adds the str pair beside it.)
run str_ret_call_field 42
## a bare `Slice(` in a file with no other prelude trigger did not pull in lib/base/slice.al, so a `Slice(T)`
## FIELD silently sized as ONE word (.len read 0 and the next field overlapped) — while the same program with
## any `Option` mention worked. The trigger is vetoed by a file-local `Slice :=` so self-declared Slices win.
run bare_slice_field 30
## INDEXING a 2-word pair FIELD (`Slice(T)` / `str`) was two independent silent faults: the READ applied inline
## `[T; N]` math (field word 0 + i*stride) to a {ptr,len} pair, and the STORE gave every range slice the str
## BYTE-view reading, so `S(v = xs[0..3])` stored xs's first ELEMENT as the data pointer. `.len` is `hi-lo` either
## way — which is exactly why the existing .len fixtures stayed green over the bug. A `str` field indexed by [i]
## returned the LEN word. Distinguished from an inline array field by the field's declared type span, so the
## arr_field_elem_* / arr_elem_agg_* paths are byte-identical.
run slice_field_elem 66
## the same pair field read through a BY-REFERENCE struct param (a wide param is a pointer, so `.len` must load
## through it) — was 0.
run slice_field_byref 56
## `return xs[lo..hi]` from a `-> Slice(T)` fn: Expr::Slice had no emit_struct_value arm and delivered 0.
run slice_range_return 36
## COMPILER SIGSEGV at CHECK time (139) on `t := s` where `s : Slice(T)` is a PARAM: a fresh `x := <value>`
## binding seeded the local's type-NAME span from the PACKED `Result(Ty, CheckErr)` carrier, which keeps only the
## TAG — so ns/nl were stack garbage (typically a whole ABSOLUTE address). `Slice` resolves to a NOMINAL struct
## decl, which armed the leak probe and made it dereference that garbage. The frozen seed carries the same
## line and the same out-of-bounds read; it just lands on a benign word — latent UB in BOTH compilers, not a
## regression. Note `Slice(u8)`/`Slice(u32)` param copies are CORRECT today, which is why no blanket reject was
## added: it would refuse spec-valid working code. 4 + 7 = 11.
run slice_param_copy_local 11
## a plain Var-to-Var copy of a VIEW (`t := s` for a `str` / `Slice(T)`) matched NO aggregate branch — a str slot
## (ek 4) and a slice slot (ek 5) both report ek 0 from var_agg_info — so only ONE word was reserved and stored:
## `t.len` read the neighbouring slot (0), and for a PARAM source the single stored word was the block ADDRESS,
## so the data pointer was wrong too. Narrow elements survived by accident: bind_param only recognizes a view for
## a known-scalar element set, so `Slice(u8)`/`Slice(u32)` bound as an ordinary 2-word STRUCT and copied fine —
## the fixture locks those widths as must-stay-correct. THIS FIX NEEDED A RESEED: the compiler's own source hit
## the bug in four places (`mut r := ""` … `r = nn` left len 0, so `if r == ""` was ALWAYS TRUE and the
## param-derived narrow type was silently discarded in aarch64/riscv64/wat; and a per-profile flag override took
## the default's length in cli.al). Copy-then-index and `Slice(Pt)` went from loud rejects to correct.
run view_var_copy 42
run view_var_reassign 11
## `q := s.ptr; deref(q)` loaded 8 BYTES because the slot carried no pointee type. It only LOOKED correct in
## return position — the exit code truncates mod 256 back to the first byte — while a comparison saw the full
## word and took the wrong branch. (A textbook case of the mod-256 gotcha masking a real bug.)
run view_ptr_deref_byte 100
## Types §6.4/§4.5: a raw pointer carries no arithmetic indexing of its own, so `p[i]` on a scalar-pointer local
## must be REJECTED, not read. Five spellings used to leaq the pointer's own frame slot and read the surrounding
## frame (0 / a neighbouring element / 95 / 80 / 104). Working spellings: deref(p), bytes(s)[i], Slice(u8)(…)[i].
build_reject_has reject_index_scalar_ptr "indexing a SCALAR local/param"
## BYTES bounded return ABI: `[u8; N]` with 1 <= N <= 8 is returned as one packed word and can be
## indexed both after binding and directly. The bound form remains x86-only; the direct form is also
## covered on AArch64 by its matching x0 carrier. The wider/non-u8 direct forms below remain located rejects.
run_x86 array_return_bound_u8 42
check_accept array_return_bound_u8
run_x86 array_return_direct_u8 42
check_accept array_return_direct_u8
run_a64 array_return_direct_u8 42
## I11 / Types §6.4 / OP-3: unsupported fixed-array RETURN shapes still reject rather than truncating a
## result or treating return registers as an inline array. The mutable `k` locks dynamic-index diagnostics.
build_reject_has reject_index_call_array_return "fixed-array-returning call result directly"
build_reject_has reject_index_call_array_return_i8_4 "fixed-array-returning call result directly"
build_reject_has reject_index_call_array_return_u8_9 "fixed-array-returning call result directly"
## `.len` of a STRUCT-element slice LOCAL read the first element's SECOND word (a silent wrong length; the slot's
## sns/snl hold the element TYPE span so it fell to the by-ref double-deref). Locks .len / .len() / an offset view
## against a scalar-element local and a Slice(Pt) PARAM.
run slice_struct_elem_len 19
## the MUTATING base::slice ops (now pub): sort / sort_by (comparator) / map_in_place / filter_into.
run slice_mutate 42
## Bounded AArch64 generic-library mono slice: injected base::slice::sort on a scalar Slice(T).
## The other injected generic slice entry points remain deliberately gated.
run a64_generic_slice_sort 42
run_a64 a64_generic_slice_sort 42
## appendix §160 sort CONFORMANCE: an introsort-class algorithm (a quadratic worst case is
## NON-CONFORMING) — was a selection sort (O(n²)); now heapsort (O(n log n) worst-case). Locks
## correctness on the adversarial reversed input + duplicates + edges + sort_by + a 20k reversed sort.
run sort_conformance 42
## an ENUM-returning call passed DIRECTLY as an argument (use(mk(...))) — the enum dual of a struct-
## returning call arg: emit_arg materializes the disc+payload into an agg-temp and passes it by-ref
## (was the scalar path → word-0-only → crash).
run enum_ret_call_arg 42
## a str payload in a GENERIC enum instance (Option(str)): the 2-word {ptr,len} rides both payload
## registers (was truncated to word 0 → the len came back 0). str-var, str-literal, and None arms.
run option_str_payload 42
## a str-returning call passed DIRECTLY as an argument (trim_end(trim_start(s)), takes(trim(s))) — the
## str dual: materialize {ptr,len} into an agg-temp, pass by-ref (was scalar path → garbage len/crash).
run str_ret_call_arg 42
## allocating str utilities in alloc::string (to_ascii_lowercase/uppercase/replace → a NEW owned
## String over the arena), read back through as_str (owned→borrowed str bridge; constructed via
## str_at, since an aggregate→aggregate bitcast drops word 1).
run str_alloc 42
run option_result_transform 42
run tail_enum_match 42
run generic_enum_ret 42
run enum_sret_wide 42
## enum-return ABI beyond 2 words: a call returning an enum whose payload is itself a MULTI-WORD enum
## (`R.Fail(Err.Bad(x))`) delivers + stages the WHOLE payload, not just its word 0 (inner disc). Both
## the intermediate-binding (`r := run(); match r`) and the direct (`match run()`) staging paths.
run enum_ret_nested_payload 42
run enum_ret_nested_direct 42
run bitcast_ptr_struct 42
run bitcast_ptr_struct_deref 42
run slice_struct_over_arena 42
run subword_ptr_deref 42
run ptr_ret_infer 42
run ambient_hashmap_value 42
run option_map 42
run generic_3param 42
run size_scalar_tparam 42
run result_map 42
run result_and_then 42
run ufcs_option_expect 42
run result_unwrap_ufcs 42
run result_method_dispatch 42
run result_ok_ufcs 42
run result_map_ufcs 42
run option_map_ufcs 42
run option_map_ufcs_struct 42
build_reject_has reject_map_ufcs_direct_struct "match recv.map(f)"
run unwrap_bound_generic_call 42
build_reject_has reject_unwrap_bound_paramladen_call "implicit-UFCS call to a multi-type-parameter"

# Grammar §4 operator precedence & associativity conformance.
# NOTE: keep these table lines comment-free — the *_sweep.sh scripts `read -r _ name want` from
# `^run [a-z]` lines and would fold a trailing comment into `want`.
# bitwise_precedence: `a | b & c` must group `a | (b & c)` = 42 (distinct tiers &>^>|), not the old (a|b)&c = 2.
run bitwise_precedence 42
# reject_chained_comparison: comparisons are non-associative — `a < b < c` must be a Parse-stage reject.
build_reject_has reject_chained_comparison "comparison operators are non-associative"
# cmp_paren_pair: a parenthesized `(a<b) == (c>d)` pair must NOT be false-rejected by the non-assoc guard.
run cmp_paren_pair 42

# tracer: the WASM→WAT backend round-trips integer arithmetic through wat2wasm+wasmtime.
check_reexport_wat
run_wat wasm_add 42
run_wat wasm_sub 42
run_wat wasm_mul 42
run_wat wasm_div 42
run_wat wasm_param 42
run_wat wasm_call 42
run_wat wasm_nested_call 42
run_wat wasm_if 42
run_wat wasm_bool 42
run_wat wasm_cmp_value 42
run_wat wasm_locals 42
run_wat wasm_local_mix 42
run_wat wasm_reassign 42
run_wat wasm_while 42
run_wat wasm_stmt_if 42
run_wat wasm_loop_sum 36
run_wat wasm_factorial 120
## cross-backend: existing scalar programs must agree x86_64 (run) == WASM (run_wat)
run_wat smoke 42
run_wat signed_local_divmod 42
run_wat inline_call 42
run_wat stack_args 42
run_wat early_return_result 42
run_wat module_mut_global 42
run_wat module_const 42
run_wat scalar_ops_library 42
run_wat int_cmp_library 42
run_wat checked_wat_shift_oob 134
run_wat unchecked_wat_shift_mask 42
run_wat section_global 42
run_wat bool_literal 42
run_wat check_typed_local 42
run_wat wasm_struct 42
run_wat wasm_struct_assign 42
run_wat wasm_struct_param 42
run_wat wasm_struct_return 42
run_wat wasm_struct_return_mut 42
run_wat wasm_nested_field 42
run_wat wasm_nested_field_write 42
run_wat wasm_enum 42
run_wat wasm_enum_payload 42
run_wat wasm_enum_param 42
run_wat wasm_enum_return 42
run_wat wasm_enum_global 42
run_wat wasm_enum_global_payload 42
run_wat wasm_value_match 42
run_wat wasm_value_match_local 42
run_wat enum_global_direct_match 42
run_wat wasm_array 42
run_wat wasm_array_index 42
run_wat wasm_struct_global 42
run_wat module_struct_const 42
run_wat module_mut_struct_global 42
run_wat wasm_stmt_match 42
run_wat wasm_struct_lit_arg 42
run_wat wasm_enum_lit_arg 42
run_wat agg_call_arg 42
run_wat ufcs_call_recv 42
run_wat ufcs_call_args 42
run_wat_out wasm_println 'hello, wasm' 42
run_wat_out wasm_print_multi 'abc' 42
run_wat_out wasm_print_val 'val = 42' 42
run_wat_out wasm_print_two '40 and 2' 42
run_wat_out wasm_print_escape $'a\nb\nc' 42
run_wat_out wasm_print_tpl_nl $'val = 42\nx' 42
run_wat operator_compare 42
run_wat hex_literal 42
run_wat wasm_nested_local 45
run_wat wasm_value_match_local_decl 42
run_wat cross_match_local 42
run_wat wat_loop_expr_value 42
run_wat wat_labeled_value_break 25
run_wat wat_labeled_value_break_aggregate 134
run_wat wat_labeled_value_break_ptr_bitcast 134
run_wat wat_labeled_value_break_global_bitcast 134
run_wat wat_commented_bitcast 134
run_wat wat_target_comment_bitcast 134
run_wat wat_inline_comment_bitcast 134
run_wat wat_grouped_comment_global_bitcast 134
run_wat wat_labeled_break 21
run_wat wat_labeled_continue 21
## Issue #44: named continue targets the outer statement while and range-for; value-loop and other
## unsupported control-flow paths remain covered by their existing fail-loud corpus rows.
run_wat loop_expr_labels 42
run_wat for_break_labels 42
check_backend_determinism
## aarch64 backend (scalar kernel): cross-validate against the same expected exits as
## the x86_64 / WASM backends — literals, params, locals+reassignment, arithmetic/comparison/bitwise,
## direct calls, value+statement `if`, `while`, `return`.
run_a64 smoke 42
run_a64 wasm_param 42
run_a64 wasm_call 42
run_a64 wasm_nested_call 42
run_a64 wasm_locals 42
run_a64 wasm_reassign 42
run_a64 wasm_if 42
run_a64 wasm_cmp_value 42
run_a64 wasm_bool 42
run_a64 wasm_stmt_if 42
run_a64 wasm_while 42
run_a64 wasm_loop_sum 36
run_a64 wasm_factorial 120
run_a64 signed_local_divmod 42
## I11/CG-7 scoping: `unchecked` drops the aarch64 div-by-zero guard → raw `sdiv x,x,0` = 0.
run_a64 unchecked_div_zero 0
## `unchecked` drops the guard, so these document HARDWARE behaviour and legitimately differ per target
## (Concurrency §6.2): x86 faults, a64 yields 0 / MIN, rv64 yields all-ones / MIN.
run_a64 unchecked_udiv_zero 41
run_a64 unchecked_rem_zero 41
run_a64 unchecked_div_min_neg1 41
run_x86 unchecked_udiv_zero 136
run_x86 unchecked_rem_zero 136
run_x86 unchecked_div_min_neg1 136
## I11/CG-8 scoping: `unchecked` drops the aarch64 `+` overflow guard → raw `add` wraps u64 MAX+1 = 0.
run_a64 unchecked_add_ovf 0
## I11/CG-8 scoping for `*`/`-`: `unchecked` drops the guard → 6148914691236517206*3 wraps to 2; 0-214 low-byte 42.
run_a64 unchecked_mul_ovf 2
run_a64 unchecked_sub_ovf 42
run_a64 inline_call 42
run_a64 stack_args 42
run_a64 stack_float_args 42
run_a64 early_return_result 42
run_a64 module_const 42
run_a64 module_mut_global 42
run_a64 section_global 42
run_a64_symbols issue41_a64_fn_mangling 42 std__probe__answer issue41_a64_fn_mangling__main
## §8.2 aarch64 value structs (scalar fields): construct `p := S(f=…)`, field read `p.f`, field write,
## and struct PARAMS by-reference (read-only; a field write through a param traps).
run_a64 wasm_struct 42
run_a64 wasm_struct_assign 42
run_a64 wasm_struct_param 42
## §8.2 aarch64 enums: construct {disc, payload}, value match on discriminant with PAYLOAD BINDING
## (E::Some(x) => x); statement-body arms deferred (fail-loud). wasm_enum unit match; wasm_enum_payload
## binds and uses the payload.
run_a64 wasm_enum 42
run_a64 wasm_enum_payload 42
run_a64 wasm_stmt_match 42
## §8.2 aarch64 arrays: construct `a := [e0,…]` (frame slots) + `a[i]` read + `a[i] = v` (runtime index).
run_a64 wasm_array 42
run_a64 wasm_array_index 42
## §8.2 aarch64 nested locals (tree-wide slot resolution): `:=` in while/if/match-arm bodies.
run_a64 wasm_nested_local 45
run_a64 wasm_value_match_local_decl 42
run_a64 cross_match_local 42
run_a64 raw_asm_a64 42
run_a64 naked_a64 42
run_a64 raw_asm_a64_sub 42
## §8.2 aarch64 print: literal + `{}`-template print/println via direct write(1,…) + __print_u64 (itoa).
run_a64_out wasm_println 'hello, wasm' 42
run_a64_out wasm_print_multi 'abc' 42
run_a64_out wasm_print_val 'val = 42' 42
run_a64_out wasm_print_two '40 and 2' 42
## riscv64 backend (scalar kernel + scalar globals): cross-validate against the same
## expected exits as the x86_64 / WASM / aarch64 backends.
run_rv64 smoke 42
run_rv64 wasm_param 42
run_rv64 wasm_call 42
run_rv64 wasm_nested_call 42
run_rv64 wasm_locals 42
run_rv64 wasm_reassign 42
run_rv64 wasm_if 42
run_rv64 wasm_cmp_value 42
run_rv64 wasm_bool 42
run_rv64 wasm_stmt_if 42
run_rv64 wasm_while 42
run_rv64 wasm_loop_sum 36
run_rv64 wasm_factorial 120
run_rv64 signed_local_divmod 42
run_rv64 unchecked_udiv_zero 42
run_rv64 unchecked_rem_zero 41
run_rv64 unchecked_div_min_neg1 41
run_rv64 inline_call 42
run_rv64 stack_args 42
run_rv64 stack_float_args 42
run_rv64 early_return_result 42
run_rv64 module_const 42
run_rv64 module_mut_global 42
run_rv64 section_global 42
## §8.3 riscv64 value structs (scalar fields): construct, field read, field write, struct PARAMS by-ref.
run_rv64 wasm_struct 42
run_rv64 wasm_struct_assign 42
run_rv64 wasm_struct_param 42
## §8.3 riscv64 enums: construct + discriminant match with PAYLOAD BINDING (stmt-body arms deferred).
run_rv64 wasm_enum 42
run_rv64 wasm_enum_payload 42
run_rv64 wasm_stmt_match 42
## §8.3 riscv64 arrays: construct + `a[i]` read + `a[i] = v` (runtime index, manual scaled address).
run_rv64 wasm_array 42
run_rv64 wasm_array_index 42
## §8.3 riscv64 nested locals (tree-wide slot resolution): `:=` in while/if/match-arm bodies.
run_rv64 wasm_nested_local 45
run_rv64 wasm_value_match_local_decl 42
run_rv64 cross_match_local 42
run_rv64 raw_asm_rv64 42
run_rv64 naked_rv64 42
run_rv64 raw_asm_rv64_sub 42
## §8.3 riscv64 print: literal + `{}`-template print/println via direct write(1,…) + __print_u64 (itoa).
run_rv64_out wasm_println 'hello, wasm' 42
run_rv64_out wasm_print_multi 'abc' 42
run_rv64_out wasm_print_val 'val = 42' 42
run_rv64_out wasm_print_two '40 and 2' 42

## Issue #306: axis-only coverage for mixed-width struct fields and narrow aggregate arguments.
## The local mixed-width, pointer-path, and narrow aggregate fixtures run on every supported backend;
## the pointer-path body is x86-only because its existing non-x86 boundary is intentionally fail-loud.
run issue306_mixed_width_local 42
run issue306_mixed_width_paths 42
run issue306_narrow_aggregate_byval 42
run_wat issue306_mixed_width_local 42
run_wat issue306_mixed_width_paths 42
run_wat issue306_narrow_aggregate_byval 42
run_a64 issue306_mixed_width_local 42
run_a64 issue306_mixed_width_paths 42
run_a64 issue306_narrow_aggregate_byval 42
run_rv64 issue306_mixed_width_local 42
run_rv64 issue306_mixed_width_paths 42
run_rv64 issue306_narrow_aggregate_byval 42

# ==================================================================================================
# THE DRIVER, part 2 — self-test, schedule, execute, report.
# ==================================================================================================
E2E_PHASE=dispatch
_e2e_check_armed || exit 1
E2E_RECORDED="$E2E_N"

## A `*_has` needle that appears in its OWN fixture's comments makes the assertion VACUOUS. The
## helpers grep the whole formatted artifact, and `fmt_test` separately asserts comment fidelity, so
## the comment is GUARANTEED to be in the text being searched: the row prints `ok` on an unfixed
## compiler. This was written down in two places — one of them a PR checkbox — and had accumulated
## twenty live violations anyway, which is why it is a check and not a sentence. Needs no compiler: the
## recording phase already holds every row's kind and arguments.
##
## Pre-existing violations live in `scripts/needle.baseline` and are REPORTED on every run rather
## than fixed here, because a banner the reader sees every time is worth more than a one-off cleanup.
## Following `idiom_gate.sh`: a baseline entry that stops occurring is `allow-unused` and does NOT
## fail, so fixing one is never punished.
NEEDLE_BASELINE="$ROOT/scripts/needle.baseline"
_e2e_needle_check() {
  local i kind name needle line key n_new=0 n_base=0 n_unused=0 seen="" base=""
  [ -f "$NEEDLE_BASELINE" ] && base="$(grep -v '^#' "$NEEDLE_BASELINE" | grep -v '^$' || true)"
  for i in $(seq 1 "$E2E_RECORDED"); do
    eval "set -- ${E2E_ROW[$i]}"
    kind="$1"
    case "$kind" in fmt_test_has|fmt_test_has_all) ;; *) continue ;; esac
    name="$2"; shift 3
    [ -f "$E2E_TEST/$name.al" ] || continue
    for needle in "$@"; do
      grep '^[[:space:]]*##' "$E2E_TEST/$name.al" | grep -qF -- "$needle" || continue
      key="$name	$needle"
      seen="$seen$key
"
      if [ -n "${ALATYR_E2E_NEEDLE_LIST:-}" ]; then printf '%s\n' "$key"; continue; fi
      if printf '%s\n' "$base" | grep -qxF -- "$key"; then
        n_base=$((n_base+1))
      else
        echo "FAIL needle_$name: the needle [$needle] appears in this fixture's own \`##\` comments, so"
        echo "     the assertion greps a string it planted itself and cannot fail. Either reword the"
        echo "     comment, or choose a needle the comment does not contain."
        n_new=$((n_new+1))
      fi
    done
  done
  if [ -n "$base" ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      printf '%s' "$seen" | grep -qxF -- "$line" || { n_unused=$((n_unused+1)); echo "allow-unused needle: ${line%%	*}"; }
    done <<< "$base"
  fi
  if [ "$n_base" != 0 ] || [ "$n_unused" != 0 ]; then
    ## `*** e2e` so `full.sh`'s existing summary grep surfaces it on the console. The debt is only
    ## worth carrying if it is visible on EVERY run; buried in a log it decays like the prose did.
    echo "*** e2e: $n_base *_has assertion(s) CANNOT FAIL — the needle is in the fixture's own comments ***"
    echo "     (grandfathered in scripts/needle.baseline; each is a vacuous row. Fixing one removes its line.)"
  fi
  [ "$n_new" = 0 ] || { echo "FAIL: $n_new new vacuous *_has assertion(s); see above"; return 1; }
  return 0
}
if [ -n "${ALATYR_E2E_NEEDLE_LIST:-}" ]; then _e2e_needle_check; exit 0; fi
_e2e_needle_check || fail=1

## Run ONE row: private scratch, private `fail`, output captured, wall time recorded.
## Called in a subshell, so nothing a row does to a shell variable can reach another row.
# The `_rx_` prefix is not decoration. Bash has DYNAMIC scope: a `local t0` here is visible to
# everything the row calls, and `native_test_runner_test` assigns `t0`/`t1` itself (it times `-j1` vs
# `-j4`). It therefore overwrote this function's own clock and the row's recorded duration came out as
# minus 1.8e15 ms. Nothing a helper can plausibly name may collide with a driver local.
_row_exec() { # idx
  local _rx_idx="$1" _rx_t0 _rx_t1
  T="$WORK/s/$_rx_idx"
  rm -rf "$T"; mkdir -p "$T" || { echo 1 0 > "$WORK/rc/$_rx_idx"; return; }
  fail=0
  E2E_PHASE=run
  # `EPOCHREALTIME`'s decimal separator follows LC_NUMERIC — with a comma locale the arithmetic below
  # would abort — so both separators are stripped. (`LC_ALL=C` is exported above as well; this is belt
  # and braces, because getting it wrong reads as a runner bug in an unrelated row.)
  _rx_t0=${EPOCHREALTIME//[.,]/}
  eval "t_${E2E_ROW[_rx_idx]}" > "$WORK/out/$_rx_idx" 2>&1
  _rx_t1=${EPOCHREALTIME//[.,]/}
  printf '%s %s\n' "$fail" "$(( (_rx_t1 - _rx_t0) / 1000 ))" > "$WORK/rc/$_rx_idx"
}

_e2e_runtime_timeout_probe() {
  _e2e_exec_timed 0.1s sleep 30 >/dev/null 2>&1
  local _e2e_rc=$?
  if [ "$E2E_RUNTIME_STATE" = timeout ]; then
    echo "FAIL e2e_timeout_probe: runtime timeout after 0.1s"
    fail=1
  else
    echo "FAIL e2e_timeout_probe: child returned rc=$_e2e_rc state=$E2E_RUNTIME_STATE"
    fail=1
  fi
}

## THE GATE OF THE GATE (AGENTS.md: "an invariant nobody has seen fail is decoration").
##
## This runs on EVERY invocation, before the suite, and proves by experiment that the machinery still
## detects. It drives the REAL helpers through the REAL `E2E_PHASE=run` path, over throwaway fixtures
## in a private fixture root, and asserts the verdict each one must produce. If any of these stops
## behaving, the suite is not run at all: a green gate whose detector is broken is worse than a red one.
_e2e_selftest() {
  local d="$WORK/selftest" keep_test="$E2E_TEST" bad=0
  mkdir -p "$d"
  printf 'main := fn() -> u64 {\n  return 42\n}\n'                    > "$d/gate_ok.al"
  printf 'main := fn() -> u64 {\n  return 41\n}\n'                    > "$d/gate_wrong_exit.al"
  printf 'main := fn() -> u64 {\n  return nonexistent_name_xyz\n}\n'  > "$d/gate_no_compile.al"
  E2E_TEST="$d"
  _st() { # expect(ok|fail), label, kind, args…
    local expect="$1" label="$2"; shift 2
    T="$WORK/s/selftest"; rm -rf "$T"; mkdir -p "$T"
    fail=0
    E2E_PHASE=run
    "$@" > "$d/last.out" 2>&1
    local got=fail; [ "$fail" = 0 ] && got=ok
    if [ "$got" = "$expect" ]; then
      echo "ok   e2e_selftest($label): $expect, as required"
    else
      echo "FAIL e2e_selftest($label): the runner said '$got', it must say '$expect'"
      sed 's/^/     | /' "$d/last.out"
      bad=1
    fi
  }
  # 1. a correct program passes …
  _st ok   accept              run gate_ok 42
  # 2. … and a WRONG EXIT CODE is caught. (Plant this by hand in a real fixture and the run must go
  #    red naming it — that experiment is what this row makes permanent.)
  _st fail wrong_exit          run gate_wrong_exit 42
  # 3. a fixture that STOPS COMPILING is a failure, not a skip.
  _st fail does_not_build      run gate_no_compile 42
  # 4. a fixture that is ABSENT is a failure (MISS), not a silent pass.
  _st fail absent_fixture      run gate_no_such_fixture 42
  # 5. a hanging child is a located FAIL row, and the self-test itself returns.
  _st fail runtime_timeout     _e2e_runtime_timeout_probe
  if grep -qF 'FAIL e2e_timeout_probe: runtime timeout after 0.1s' "$d/last.out"; then
    echo "ok   e2e_selftest(runtime_timeout): bounded child produced a concrete FAIL row"
  else
    echo "FAIL e2e_selftest(runtime_timeout): timeout row was not concrete"
    bad=1
  fi
  # 6. a legal timeout-looking child status is preserved when the completion marker is present.
  local status_124 status_137 state_124 state_137 capture_status capture_state capture_output
  _e2e_exec_timed 0.1s bash -c 'exit 124' >/dev/null 2>&1; status_124=$?; state_124="$E2E_RUNTIME_STATE"
  _e2e_exec_timed 0.1s bash -c 'exit 137' >/dev/null 2>&1; status_137=$?; state_137="$E2E_RUNTIME_STATE"
  if [ "$state_124" = exited ] && [ "$status_124" = 124 ] && [ "$state_137" = exited ] && [ "$status_137" = 137 ]; then
    echo "ok   e2e_selftest(runtime_status): preserved child exits 124 and 137"
  else
    echo "FAIL e2e_selftest(runtime_status): 124=$status_124/$state_124 137=$status_137/$state_137"
    bad=1
  fi
  _e2e_exec_capture_combined "$d/runtime_capture.out" bash -c 'printf "runtime stdout\n"; printf "runtime stderr\n" >&2; exit 124'
  capture_status=$?
  capture_state="$E2E_RUNTIME_STATE"
  capture_output="$(<"$d/runtime_capture.out")"
  if [ "$capture_state" = exited ] && [ "$capture_status" = 124 ] \
    && [ "$capture_output" = $'runtime stdout\nruntime stderr' ]; then
    echo "ok   e2e_selftest(runtime_capture): preserved combined stdout/stderr and status 124"
  else
    echo "FAIL e2e_selftest(runtime_capture): status=$capture_status state=$capture_state output=[$capture_output]"
    bad=1
  fi
  # 7. `build_reject` is satisfied only by a NON-ZERO build …
  _st ok   build_reject_hit    build_reject gate_no_compile
  # 8. … and must NOT be satisfied by a program that builds fine.
  _st fail build_reject_miss   build_reject gate_ok
  # 9. `build_reject_has`'s NEEDLE is load-bearing: an unsatisfiable needle must fail even though the
  #    build did fail (this is the difference between `build_reject` and `build_reject_has`).
  _st fail needle_unsatisfiable build_reject_has gate_no_compile 'no compiler will ever print this'
  # 10. … while the real diagnostic satisfies it.
  _st ok   needle_satisfied    build_reject_has gate_no_compile 'unbound name at line 2 in gate_no_compile'
  # 11. `check_accept`/`check_reject` are not interchangeable.
  _st ok   check_accept_hit    check_accept gate_ok
  _st fail check_accept_miss   check_accept gate_no_compile
  _st ok   check_reject_hit    check_reject gate_no_compile
  _st fail check_reject_miss   check_reject gate_ok
  # 12. artifacts land in the ROW's scratch directory and nowhere else — the property that makes two
  #     rows naming one fixture safe. A helper writing to a name-keyed path under `target/` would
  #     leave this file unwritten (and clobber the other row's binary).
  T="$WORK/s/selftest"; rm -rf "$T"; mkdir -p "$T"; fail=0; E2E_PHASE=run
  run gate_ok 42 > "$d/last.out" 2>&1
  if [ -f "$T/e2e_gate_ok.out" ] && [ ! -e "$ROOT/target/e2e_gate_ok.out" ]; then
    echo "ok   e2e_selftest(row_isolation): the row's artifact is under \$T, not target/"
  else
    echo "FAIL e2e_selftest(row_isolation): artifact not confined to \$T ($T)"
    bad=1
  fi
  # 13. arming really happened: the table-facing name is the recording stub, and the CLONE is the
  #     helper itself (not the stub, and not a textual approximation of it — cloning the clone
  #     reproduces it exactly, which is the `declare -f` round-trip the whole scheme rests on).
  if declare -f run | grep -q '_dispatch run'; then
    echo "ok   e2e_selftest(armed): the table-facing helper is the recording stub"
  else
    echo "FAIL e2e_selftest(armed): 'run' was not armed — the table would execute inline, serially"
    bad=1
  fi
  if declare -f t_run | grep -q '_dispatch'; then
    echo "FAIL e2e_selftest(clone): t_run is the stub, not the helper — every row would be a no-op"
    bad=1
  else
    local b2
    b2="$(declare -f t_run)"; b2="${b2#t_run}"
    eval "_e2e_clone_probe$b2"
    if [ "$(declare -f t_run | tail -n +2)" = "$(declare -f _e2e_clone_probe | tail -n +2)" ]; then
      echo "ok   e2e_selftest(clone): the helper survives the declare -f round trip byte-identically"
    else
      echo "FAIL e2e_selftest(clone): the declare -f round trip is not faithful"
      bad=1
    fi
    unset -f _e2e_clone_probe
  fi
  unset -f _st
  E2E_TEST="$keep_test"
  E2E_PHASE=dispatch
  fail=0
  [ "$bad" = 0 ] && return 0
  echo "*** e2e: THE SELF-TEST FAILED — the runner no longer detects the failures it must detect."
  echo "*** e2e: the suite was NOT run: a green result from a broken detector is worse than a red one. ***"
  return 1
}

## Longest-first scheduling. Row cost varies by four orders of magnitude (a `check_accept` is ~40 ms;
## `ext_test env_size_test` is 83 s), and with 12 workers the makespan is dominated by whether the
## long rows START early. Costs come from the PREVIOUS run of this worktree (`target/e2e_cost.tsv`,
## keyed by the row's own command text, so reordering the table cannot misattribute them); an unknown
## row sorts last. This affects the ORDER ROWS START, never the order they are PRINTED, so the log is
## unaffected — deleting the cost file changes the wall time and nothing else.
COSTFILE="$ROOT/target/e2e_cost.tsv"
_e2e_schedule() {
  local i key cost
  declare -A prev=()
  if [ -f "$COSTFILE" ]; then
    while IFS="$(printf '\t')" read -r cost key; do
      [ -n "${key:-}" ] && prev["$key"]="$cost"
    done < "$COSTFILE"
  fi
  : > "$WORK/sched.in"
  for ((i = 1; i <= E2E_N; i++)); do
    key="${E2E_ROW[i]}"
    cost="${prev[$key]:-0}"
    printf '%s\t%s\n' "$cost" "$i"
  done >> "$WORK/sched.in"
  sort -k1,1nr -k2,2n "$WORK/sched.in" | cut -f2 > "$WORK/sched.txt"
}

## Run the schedule on `$JOBS` workers. With `ALATYR_JOBS=1` this is a strict serial run in table
## order (the schedule still applies, but one row at a time cannot interleave).
_e2e_dispatch() {
  local running=0 idx
  while read -r idx; do
    while [ "$running" -ge "$JOBS" ]; do wait -n 2>/dev/null; running=$((running - 1)); done
    ( _row_exec "$idx" ) &
    running=$((running + 1))
  done < "$WORK/sched.txt"
  while [ "$running" -gt 0 ]; do wait -n 2>/dev/null; running=$((running - 1)); done
}

## Print every row's output in TABLE ORDER and account for all of it.
_e2e_report() {
  local i rc ms executed=0 lost=0 failed=0
  : > "$COSTFILE.new"
  for ((i = 1; i <= E2E_N; i++)); do
    if [ ! -f "$WORK/rc/$i" ] || [ ! -f "$WORK/out/$i" ]; then
      echo "FAIL row $i (${E2E_ROW[i]}): the runner produced no result for this row"
      lost=$((lost + 1)); fail=1
      continue
    fi
    read -r rc ms < "$WORK/rc/$i"
    # Bash prints its OWN job-status line when a child dies of a signal ("… 12345 Illegal instruction
    # …"), on the shell's stderr — which, for a row, is this file. Dozens of fixtures trap on purpose,
    # so 37 such lines are normal, and each carries a PID: two runs of an unchanged tree could never
    # produce identical logs, and a diff between runs would be useless. Only the PID varies, so the PID
    # is replaced. The line is NOT dropped — a message from the shell is still a message.
    sed 's|^\(scripts/e2e\.sh: line [0-9]*: \)[0-9][0-9]*\( \)|\1<pid>\2|' "$WORK/out/$i"
    executed=$((executed + 1))
    [ "$rc" = 0 ] || { failed=$((failed + 1)); fail=1; }
    # The recorded duration is the runner's own bookkeeping, so an impossible value means a helper
    # overwrote a driver variable through bash's dynamic scope (that has happened — see `_row_exec`).
    # Say so instead of silently poisoning the schedule: whatever else that helper clobbered is next.
    case "$ms" in
      ''|*[!0-9]*) echo "FAIL row $i (${E2E_ROW[i]}): recorded duration '$ms' is not a number — a helper"
                   echo "     assigned to one of the driver's own variables (dynamic scope); see _row_exec"
                   fail=1; ms=0 ;;
      *) [ "$ms" -le 86400000 ] || { echo "FAIL row $i (${E2E_ROW[i]}): recorded duration ${ms}ms is impossible"; fail=1; ms=0; } ;;
    esac
    printf '%s\t%s\n' "$ms" "${E2E_ROW[i]}" >> "$COSTFILE.new"
  done
  mv -f "$COSTFILE.new" "$COSTFILE" 2>/dev/null || true
  E2E_EXECUTED="$executed"; E2E_LOST="$lost"; E2E_FAILED="$failed"
}

if [ -n "$FILTER" ]; then
  echo "=== e2e: FILTERED run (ALATYR_E2E_FILTER='$FILTER') — this is NOT the gate ==="
fi
_e2e_selftest || exit 1

# Apply the filter, if any, by dropping unselected rows from the recorded table. The gate never sets
# one; the iteration front end (scripts/e2e_fast.sh) does.
if [ -n "$FILTER" ]; then
  declare -a KEEP=()
  keptn=0
  for ((i = 1; i <= E2E_N; i++)); do
    case "${E2E_ROW[i]}" in *"$FILTER"*) keptn=$((keptn + 1)); KEEP[keptn]="${E2E_ROW[i]}" ;; esac
  done
  [ "$keptn" -gt 0 ] || { echo "FAIL: no row matches the filter '$FILTER'"; exit 1; }
  unset E2E_ROW
  declare -a E2E_ROW=()
  for ((i = 1; i <= keptn; i++)); do E2E_ROW[i]="${KEEP[i]}"; done
  E2E_N="$keptn"
fi

echo "=== e2e: $E2E_N rows, $E2E_KINDS assertion kinds, -j$JOBS (compiler: $CC) ==="
_e2e_schedule
_e2e_dispatch
_e2e_report

# The counts. `assertions` is the number of verdict lines the rows emitted — the label set a coverage
# comparison is made over; a runner that dropped rows would show it falling. `skipped` counts
# environment gates (an absent cross-toolchain is not a failure); `missing` counts absent fixtures,
# which ARE failures and are already reflected in `failed`.
E2E_ASSERTIONS=$(grep -chE '^(ok|FAIL|MISS|skip) ' "$WORK"/out/* 2>/dev/null | awk '{s += $1} END {print s + 0}')
E2E_SKIPPED=$(grep -ch '^skip ' "$WORK"/out/* 2>/dev/null | awk '{s += $1} END {print s + 0}')
E2E_MISSING=$(grep -ch '^MISS ' "$WORK"/out/* 2>/dev/null | awk '{s += $1} END {print s + 0}')
if [ "$E2E_EXECUTED" != "$E2E_N" ]; then
  echo "FAIL: executed $E2E_EXECUTED of $E2E_N rows — $E2E_LOST were lost by the runner, not by a test"
  fail=1
fi
# Unfiltered, every row the table recorded must have been selected. `recorded` is printed either way, so
# a filtered run cannot be mistaken for full coverage by reading the counts.
if [ -z "$FILTER" ] && [ "$E2E_N" != "$E2E_RECORDED" ]; then
  echo "FAIL: the table recorded $E2E_RECORDED rows but only $E2E_N were selected, with no filter set"
  fail=1
fi
echo "*** e2e: rows=$E2E_N recorded=$E2E_RECORDED executed=$E2E_EXECUTED lost=$E2E_LOST assertions=$E2E_ASSERTIONS skipped=$E2E_SKIPPED missing=$E2E_MISSING failed=$E2E_FAILED jobs=$JOBS filter='$FILTER' ***"
[ "$fail" = 0 ] && echo "*** e2e: all green ***" || echo "*** e2e: FAILURES ***"
exit "$fail"
