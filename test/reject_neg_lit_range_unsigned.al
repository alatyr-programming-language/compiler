## Types §9.1 (#602) — a written negative literal is out of range for EVERY unsigned type, and the
## bound that catches it is the one §9.1 states: representability in the target type is a
## compile-time judgement, and −1 is not representable in `u8`. This refusal is NEW beyond the
## defect #602 opens with, and it is deliberately inside that unit rather than deferred: it follows
## from the same one-line rule, no corpus row depends on the old behaviour, and separating it would
## have cost a second seed promotion for one predicate row.
##
## Measured on the parent, this program compiled clean on all four backends and RAN TO 255 — −1
## wrapped into the byte. The mathematical zero written as `-0` is NOT this case and stays accepted;
## `accept_neg_lit_range_edges` carries that control.
main := fn() -> u64 {
  n : u8 = -1
  u64(n)
}
