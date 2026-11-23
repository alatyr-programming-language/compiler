## Issue #1867 — an immutable local declared in an `if` block, named like an enclosing `mut` local,
## shadows it only inside the block (Declarations §5, §6.1: "the outer name is again visible after the
## inner scope ends"). The checker kept the inner binding in effect after the block and refused the
## later `v = 42` as an immutable binding; the `else` arm and a nested block did the same.
## Due 42: `v` is 42 after the first block, `r` stays 0 through both blocks, `w` is 0 after the second.
## spec: Declarations §5, §6.1
main := fn() -> u64 {
  mut v : u64 = 0
  mut r : u64 = 0
  if r == 0 {
    v : u64 = 5
    r = v - 5
  }
  v = 42
  mut w : u64 = 7
  if r != 0 {
    r = 1
  } else {
    w : u64 = 3
    if w == 3 {
      v : u64 = 9
      r = v - w - 6
    }
    r = r + w - 3
  }
  w = 0
  v + r + w
}
## expect: run 42
