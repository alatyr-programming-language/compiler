## e2e — MUTABLE array module GLOBAL (`mut TABLE := [..]`). An array global gets `.data` storage as N
## ascending 8-byte cells; `TABLE[i]` loads element i (`leaq LABEL(%rip)` + indexed word load), and
## `TABLE[i] = v` stores it — runtime index, shared mutable state. Here `TABLE[2]` is rewritten from a
## read+arith (10 + 7 = 17), then a while-loop sums all three by index. Returns 10 + 15 + 17 = 42.
mut TABLE := [10, 15, 100]
main := fn() -> u64 {
  TABLE[2] = TABLE[0] + 7
  mut acc := 0
  mut i := 0
  while i < 3 {
    acc = acc + TABLE[i]
    i = i + 1
  }
  acc
}
