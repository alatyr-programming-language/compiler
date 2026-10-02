## §8 backend breadth: the integer conversion `u8(x)` exists on EVERY backend (x86_64, aarch64,
## riscv64, wasm), checked by default and masking inside `unchecked`.
##
## Types §4.2 (narrow row): a narrowing `T(v)` is checked by default — it traps when the value does not
## fit — and inside an `unchecked` scope it truncates (CG-7). This row asserted 42 for the CHECKED
## `u8(u16(810))`, freezing a silent wrong value into the corpus oracle (#872). It now writes the two
## spec forms side by side: the checked in-range `u8(k)` keeps its value, and the masking of the
## out-of-range VALUE 810 is written inside `unchecked`, where §4.2 makes it the defined result
## (810 & 0xFF = 42). `test/conv_narrow_trap.al` holds the checked out-of-range form, which traps;
## `test/reject_conv_narrow_literal.al` keeps the refused literal spelling `u8(810)` (§9.1, #564).
## The checked u8(42) keeps 42; the unchecked u8(810) masks to 42.
main := fn() -> u64 {
  k : u16 = 42
  v : u16 = 810
  c := u64(u8(k))
  m := u64(unchecked u8(v))
  if c != 42 { return 1 }
  m
}
