## Issue #580, closed-set witness — BIT 1, a TYPE used as an associated-function namespace.
##
## `Option` names no module; it is a declaration with a field/variant list, and a `::` head may
## name one. Its kind mask is exactly 2, so this fixture is the non-vacuity witness for that arm.
main := fn() -> u64 {
  o : Option(u64) = Option(u64).Some(63)
  Option::unwrap(u64, o)
}
