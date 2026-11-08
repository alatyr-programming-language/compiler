## #1518 — Types §4.6 dispatch step (2) selects a `@convert` whose parameter ACCEPTS the operand's
## type. The one conversion to `P` here takes a `bool`, and no conversion accepts the integer operand,
## so `P(42)` denotes no conversion and `P` is a struct (no builtin step (3) applies): the program is
## ill-formed. Before the fix the site called `from_bool` anyway and the program answered 7.
P := struct { a : u64, b : u64 }
from_bool := @convert fn(x : bool) -> P { return P(a = 7, b = 0) }
main := fn() -> u64 {
  p := P(42)
  return p.a
}
## expect: reject "accepts the operand's type"
