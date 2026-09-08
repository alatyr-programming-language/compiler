## Issue #557 / Control Flow §5.1 — scrutinee shape 3 of 6: an INFERRED local binding (`c := C.R`).
## The binding records the enum under the hidden aggregate tag the literal recovery writes, which the
## old checker did not recognise, so this program compiled silently. `B` is uncovered and there is no
## `_` default, so it must be refused.
C := enum { R, G, B }
main := fn() -> u64 {
  c := C.R
  match c { R => { return 1 }; G => { return 2 } }
  return 0
}
