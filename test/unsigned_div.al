## I11: UNSIGNED division must reduce a high-bit `u64` correctly on EVERY backend. The native
## backends (aarch64/riscv64) and WASM formerly emitted the SIGNED division op unconditionally
## (`sdiv` / `div` / `i64.div_s`), reading a high-bit value as negative → a wrong (non-trapping)
## result: a silent miscompile vs the x86_64 `divq` path. Now `/`/`%` route to the unsigned op
## unless an operand is a known `iN`, matching x86_64's `is_signed_expr` rule on all four backends.
## (2^64 - 1) / 2^58 = 63 unsigned; as SIGNED it is -1 / 2^58 = 0 (the old bug). The small quotient
## keeps the process exit code identical across the native and WASM exit conventions.
udiv := fn(a : u64, b : u64) -> u64 { return a / b }
main := fn() -> u64 { return udiv(18446744073709551615, 288230376151711744) }
