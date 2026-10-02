## §8 backend breadth: a SIGNED integer conversion `i8(x)` sign-extends the low 8 bits on EVERY
## backend (x86_64 movsbq, aarch64 sxtb, riscv64 slli+srai, wasm i64.extend8_s), checked by default
## and reinterpreting inside `unchecked`.
##
## Types §4.4: `T(value)` preserves the value; I11: a checked operation traps on a bad input. So a
## signedness change of a value the target cannot hold (§4.2 numeric row) traps in a checked scope and
## is the bit reinterpretation inside `unchecked`. This row asserted 42 for the CHECKED `i8(u8(200))`,
## freezing a silent wrong value into the corpus oracle (#881). It now writes the two spec forms side by
## side: the checked in-range `i8(k)` keeps its value, and the sign-extension of the u8 VALUE 200 is
## written inside `unchecked`, where it is the defined result (200 sign-extended from 8 bits = -56).
## `test/conv_signed_trap.al` holds the checked unrepresentable form, which traps;
## `test/reject_conv_signed_literal.al` keeps the refused literal spelling `i8(200)` (§9.1, #564).
## The checked i8(98) keeps 98; -56 + 98 = 42.
main := fn() -> u64 {
  k : u8 = 98
  v : u8 = 200
  c := i8(k)
  m := unchecked i8(v)
  return u64(m + c)
}
