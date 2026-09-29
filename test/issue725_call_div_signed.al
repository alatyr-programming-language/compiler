## Issue #725 — dividing the result of a CALL returning a negative `i64`. The three non-x86 emitters took
## a call operand as unsigned: aarch64 and riscv64 answered 185 and wasm 1 on the parent — the unsigned
## quotient of the two's-complement bits — where the signed answer, -28, gives 42. Found by
## `scripts/progen.py` (seed 32). The uncalled function is the prelude trigger (#532).
progen_trigger := fn() -> u64 {
  match checked_add(u8(1), u8(1)) { Some(v) => { u64(v) } None => { 0 } }
}
f1 := fn() -> i64 { return unchecked (1 - 255) }
main := fn() -> u64 {
  q : i64 = unchecked (f1() / 9)
  if q == (0 - 28) { return 42 }
  return u64(unchecked (q + 100))
}
