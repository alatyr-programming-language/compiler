## e2e (#966, #964 — Types §4 / Concurrency §6.2: `unchecked` does not change a value's SIGNEDNESS).
## `/` and `%` take their signedness from sema's RECORD of the operator. The twins asked their own shape
## query instead, which proves a `Var` signed from its annotation and NOTHING about a literal-only `Bin`
## dividend — so `(0 - 65535) % 7` fell to the unsigned default: the divisor became 9 instead of 7 and
## `65535 % 9` answered 6 where 1 is due. A silent wrong value on aarch64, riscv64 and wasm alike
## (progen seed 2074802405; the shape also needs an unrelated `if` in value position in the same
## function to reach the emitter that asked — that is what made it hard to see).
## Values: (-65535 % 7) is -1 truncated, so the divisor is 7 and 65535 % 7 is 1.
g := fn(q : i64) -> i64 { return 3 }
d := fn(p11 : i64, p12 : i64, p13 : i64) -> i64 {
  mut v : i64 = (if 1 != 1 { g(1) } else { 3 })
  return unchecked (p13 % unchecked (((0 - 65535) % 7) + 8))
}
main := fn() -> u64 {
  mut b : i64 = d(7, 255, 65535)
  if b != 1 { return 100 + u64(b + 200) }
  mut s : i64 = unchecked ((0 - 100) / 7)
  if s != -14 { return 200 + u64(s + 200) }
  return 42
}
