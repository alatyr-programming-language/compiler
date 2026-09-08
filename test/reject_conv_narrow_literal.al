## Types §9.1 (#564) — the literal spelling `conv_narrow` used to assert a value for. 810 is not
## representable in u8, so §9.2's literal-refining constructor form makes this a compile error: "a
## literal outside the target type's range is a compile error (I11), never a silent wrap." Measured on
## the parent, this built on all four backends and RAN TO 42 — the wrap the invariant forbids, and the
## number `conv_narrow` asserted, which is why that row was rewritten onto a representable literal
## rather than left to freeze the wrap into the oracle (#527).
main := fn() -> u64 { return u8(810) }
