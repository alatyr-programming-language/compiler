## Types §9.1 (#564) — the literal spellings `int_narrow_conv` used to assert a value for. None of
## 70000, 810 or 4294967338 is representable in the type its constructor names, so each is a compile
## error under §9.2's literal-refining constructor form rather than a silent wrap to 4464 / 42 / 42.
## The refusal is located at the FIRST one the walk reaches; the other two are asserted case by case
## in `issue564_ctor_literal_range_test`. Measured on the parent, this built on all four backends and
## RAN TO 42 — the number `int_narrow_conv` asserted, which is why that row was rewritten onto
## representable literals rather than left to freeze the wrap into the oracle (#527).
main := fn() -> u64 {
  b := u64(u16(70000)) / 1488
  a := u64(u8(810)) / 4
  c := u64(u32(4294967338)) / 42
  a + b + c + 28
}
