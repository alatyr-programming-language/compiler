## Issue #1848 — after a `for` loop whose variable is named like an enclosing local, the name denotes
## the enclosing local again (Declarations §5, §6.1). The checker kept typing it as the loop variable,
## an `i64` range element, and refused `v + r` as a mix of signedness; a binding declared inside a
## `while` or `loop` body leaked over the enclosing one the same way.
## Due 42: `v` is 39 after the loop, `r` sums 0 + 1 + 2, then `n` is 0 after the `while` and the `loop`.
## spec: Declarations §5, §6.1
main := fn() -> u64 {
  mut v : u64 = 0
  mut r : u64 = 0
  for v in 0..3 { r = r + u64(v) }
  v = 39
  mut n : u64 = 1
  while n == 1 {
    n : i64 = 2
    if n == 2 { break }
  }
  n = n - 1
  loop {
    n : bool = true
    if n { break }
  }
  v + r + n
}
## expect: run 42
