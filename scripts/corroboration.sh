#!/usr/bin/env bash
# corroboration.sh — for the programs where ir_diff says the two x86 paths disagree, ask the other
# backends. `alatyr <verb> prog.al` writes target assembly (or .wat) to stdout; the twins are then
# assembled and linked with their own cross tools and run under qemu, wasm under wasmtime. The exit
# code IS the program's answer (these programs `exit` with their value), so agreement across four
# independent backends is the oracle — no expected value is written down here on purpose.
#
# A trap is a trap whatever its number: x86_64 raises SIGILL (132) on `ud2`, the twins raise SIGTRAP
# (133) on `brk #0`/`ebreak`, wasm aborts (134). Raw codes compared across backends would call that a
# disagreement, so every signal death prints as TRAP(<sig>).
#
# usage: scripts/corroboration.sh test/foo.al [test/bar.al ...]
cd "$(dirname "$0")/.." || exit 1   # the repo root: $PWD/target/debug/alatyr resolves from here
BIN=${ALATYR:-$PWD/target/debug/alatyr}
[ -x "$BIN" ] || { echo "corroboration: no compiler at $BIN (build it first)" >&2; exit 2; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

norm() { # <rc> — RUN<n> or TRAP(<sig>)
  local rc="$1"
  if [ "$rc" -ge 128 ]; then printf 'TRAP(%s)' "$((rc - 128))"; else printf 'RUN%s' "$rc"; fi
}
# run <exe> [args...] — the child runs in its own bash so a signal death is reported by THAT shell and
# swallowed with its stderr rather than interrupting this one. $0 carries the program, "$@" its args, so
# the program is not passed to itself as an argument.
run() { # <exe> [args...] -> sets RC
  local exe="$1"; shift
  bash -c 'timeout 30 "$0" "$@" >/dev/null 2>&1' "$exe" "$@" >/dev/null 2>&1
  RC=$?
}

for t in "$@"; do
  printf '%-42s' "$(basename "$t" .al)"
  for b in x86 x86-ir aarch64 riscv64 wat; do
    case "$b" in
      x86)
        # the x86 path has no verb of its own: `alatyr -o exe prog.al` is the default emitter and
        # `x86-ir` the dev verb — that is how ir_diff invokes them.
        if timeout 60 "$BIN" -o "$W/p.x86" "$t" >"$W/b.log" 2>&1 </dev/null; then
          run "$W/p.x86"; printf '%s=%-9s ' "$b" "$(norm $RC)"
        else printf '%s=REFUSE    ' "$b"; fi ;;
      x86-ir)
        if timeout 60 "$BIN" x86-ir -o "$W/p.ir" "$t" >"$W/b.log" 2>&1 </dev/null; then
          run "$W/p.ir"; printf '%s=%-9s ' "$b" "$(norm $RC)"
        else printf '%s=REFUSE    ' "$b"; fi ;;
      aarch64|riscv64)
        if timeout 60 "$BIN" "$b" "$t" > "$W/p.s" 2>"$W/b.log" </dev/null \
           && "$b-unknown-linux-gnu-as" "$W/p.s" -o "$W/p.o" 2>/dev/null \
           && "$b-unknown-linux-gnu-ld" "$W/p.o" -o "$W/p.elf" 2>/dev/null; then
          run "$(command -v qemu-$b)" "$W/p.elf"; printf '%s=%-9s ' "$b" "$(norm $RC)"
        else printf '%s=REFUSE    ' "$b"; fi ;;
      wat)
        if timeout 60 "$BIN" wat "$t" > "$W/p.wat" 2>"$W/b.log" </dev/null \
           && wat2wasm "$W/p.wat" -o "$W/p.wasm" 2>/dev/null; then
          run "$(command -v wasmtime)" -C cache=n "$W/p.wasm"; printf '%s=%-9s ' "$b" "$(norm $RC)"
        else printf '%s=REFUSE    ' "$b"; fi ;;
    esac
  done
  echo
done
