## Issue #803 / Types §9.1, Declarations §3.4 — an array LITERAL argument takes its element type from
## the parameter `[u8; 2]`, so `300` is out of range there, exactly as `f(300)` is for a scalar `u8`
## parameter. The parent accepted this call.
f := fn(xs : [u8; 2]) -> u64 { return u64(xs[1]) }
main := fn() -> u64 { return f([1, 300]) }
