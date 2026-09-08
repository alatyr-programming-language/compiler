## Types §9.1 (#564) — the literal spelling `conv_signed` used to assert a value for. 200 is not
## representable in i8 (its bound is 127), so §9.2's literal-refining constructor form makes this a
## compile error, never the silent sign-extended wrap to -56. Measured on the parent, this built on
## all four backends and RAN TO 42 — the number `conv_signed` asserted, which is why that row was
## rewritten onto a representable literal rather than left to freeze the wrap into the oracle (#527).
main := fn() -> u64 { return i8(200) + 98 }
