## IR slice 1c (`docs/ir-slice-1.md` §4, #777): `and`/`or` short-circuit on the three twins once a function
## is selected from the shared IR, where they are `if` regions over a `bool` (`docs/ir.md` §4). The right
## operand here divides by zero, so evaluating it traps. On the legacy twin emitters, which combine both
## operands bitwise, this program trapped (aarch64/riscv64 133, wasm 134). x86_64 and the IR-selected
## twins answer 42.
zero := fn() -> u64 { return 0 }
boom := fn() -> bool { return 7 / zero() == 1 }
main := fn() -> u64 {
  mut r : u64 = 0
  if false and boom() { r = 99 }
  if true or boom() { r = r + 40 }
  t := false and boom()
  if not t { r = r + 2 }
  return r
}
