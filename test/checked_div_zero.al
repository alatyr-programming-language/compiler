## I11 / CG-7: checked division by a runtime-zero divisor must TRAP on EVERY backend
## (x86_64 #DE, aarch64 `brk`, riscv64 `ebreak`, wasm div trap) — never silently return a
## wrong result. Before the guard, aarch64 `sdiv`/`msub` and riscv64 `div`/`rem` by zero
## returned 0 / all-ones (a valid binary, wrong exit) — a silent miscompile. The divisor is
## passed at runtime so no backend can constant-fold it away. The `run` sweeps assert every
## non-x86 backend TRAPS (exit >= 128) rather than returning a wrong low exit code.
divide := fn(a : i64, b : i64) -> i64 { return a / b }
main := fn() -> i64 { return divide(42, 0) }
