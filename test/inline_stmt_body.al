## e2e — statement-body `@inline` expansion (the num.al operator shape): a body with a local `out`, a
## comptime-if arch guard, an arch intrinsic, and a trailing `return`. The callee's body-locals are
## aliased into the inline scratch past the params, the body is emitted inline, and `return out` is
## redirected to deliver the value (not jump the caller's epilogue). mydiv(84, 2) = 84/2 = 42.
##
## The gate carries an ELSE with a PORTABLE fallback (Tooling §2.7). `target.*` is the resolved
## SELECTED machine model, so on aarch64/riscv64/wat the `== Arch.x86_64` arm is FALSE — and with no
## else this body left `out` at `a`, returning 84 instead of 42: a silent WRONG value, the one failure
## the backends forbid. `x86_64.divq` remains the tested path on x86_64; every other target takes the
## ordinary `a / b` its own backend lowers. A library body with no implementation for the selected
## target must fall back or be ABSENT, never fall through (see `lib/std/thread.al`'s `when` gate).
@inline mydiv := fn(a : u64, b : u64) -> u64 {
  mut out : u64 = a
  comptime if target.arch == Arch.x86_64 { x86_64.divq(out, b) } else { out = a / b }
  return out
}
main := fn() -> u64 {
  mydiv(84, 2)
}
