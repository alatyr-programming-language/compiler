## e2e reject — issue #469, the mixed-type guard. `base::derive::eq` is MONOMORPHIZED on one `T`,
## and the mono pre-pass registers the instance from the LEFT operand alone, so a comparison whose
## two aggregate operands name DIFFERENT types cannot be routed structurally: it would be answered
## through the wrong instance, or fail to link.
##
## The parent accepted this program and answered `P(x = 5, y = 7) == Q(a = 5, b = 7)` as EQUAL
## (measured 51 on 495cc51 — the then arm), because both operands materialized as the constant `$0`
## and the two `$0`s compared equal. Two values of unrelated types reading equal is exactly the
## silent wrong value the class is about, so the guard proves the two operand type names agree and
## stops the build with a located message when they do not.
##
## Whether `check` should have refused this as a type error before lower ever saw it is a separate
## question; a located reject in the lowering is the conservative floor either way.

P := struct { x : u64, y : u64 }
Q := struct { a : u64, b : u64 }

main := fn() -> u64 {
  if P(x = 5, y = 7) == Q(a = 5, b = 7) { return 51 }
  return 52
}
