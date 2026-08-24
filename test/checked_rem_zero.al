## I11 / CG-13: a checked REMAINDER `%` by a runtime-zero divisor is the same guard as `/` (both
## lower to the one divide instruction) and must fail through the same direct inline trap — `ud2`
## on x86_64 (SIGILL, exit 132), `brk #0` on aarch64, `ebreak` on riscv64 — emitted BEFORE the
## divide, never the hardware `#DE` (SIGFPE, exit 136) x86_64 raised on its own before the guard.
## Runtime divisor, so the guard cannot be constant-folded away. `unchecked_rem_zero` is the
## `unchecked` counterpart (guard absent, the hardware's own remainder value).
rem := fn(a : u64, b : u64) -> u64 { return a % b }
main := fn() -> u64 { return rem(42, 0) }
