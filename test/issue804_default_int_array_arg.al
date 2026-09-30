## Issue #804 / Types §9.1, Declarations §3.2/§3.4 — `a := [1, 7]` has no context, so its literals take
## the documented default, the native signed integer: `a` is an `[i64; 2]`. Passed where `[u8; 2]` is
## declared it is a type mismatch (only widening is implicit, Types §4.3). The parent accepted it and
## the callee read 0 for `xs[1]`, since the word array does not have the `[u8; 2]` layout.
f := fn(xs : [u8; 2]) -> u64 { return u64(xs[1]) }
main := fn() -> u64 {
  a := [1, 7]
  return f(a)
}
