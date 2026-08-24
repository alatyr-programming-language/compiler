## I11 / CG-13: an UNSIGNED checked `/` by a runtime-zero divisor traps through the ONE failure
## mechanism of the whole checked-guard family — the direct inline trap emitted BEFORE the divide
## (`ud2` on x86_64 → SIGILL → exit 132, `brk #0` on aarch64, `ebreak` on riscv64). Before the guard
## x86_64 let the hardware `#DE` fault instead (SIGFPE → exit 136) while every other guard in the
## family exited 132 — two observable failures for one family, the divergence CG-13 closes. The
## signed companion is `checked_div_zero`; `unchecked_udiv_zero` proves the guard is scoped away.
## The divisor arrives as a runtime parameter, so no backend can constant-fold the guard away.
divide := fn(a : u64, b : u64) -> u64 { return a / b }
main := fn() -> u64 { return divide(42, 0) }
