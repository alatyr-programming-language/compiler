## DEFER (§9.3): a value-bearing `loop` (`x := loop { … break 5 }`) with a `defer` in its body — proves
## a break VALUE and the loop's defer drain COEXIST (the value is pushed first, the drain's pushes sit
## above it, and the done-label still converges with exactly one value). `f`: iteration 1 (i<2) falls
## through and drains bump(1) → ACC 1; iteration 2 `break 5`s — its defer bumps too → ACC 11 — and
## yields x=5; `ACC + x` = 16. If the defer dropped on the value-break, ACC would be 1 + 5 = 6.
mut ACC : u64 = 0
bump := fn(n : u64) -> u64 { ACC = ACC * 10 + n ; 0 }
f := fn() -> u64 {
  mut i : u64 = 0
  x := loop {
    defer bump(1)
    i = i + 1
    if i >= 2 { break 5 }
  }
  return ACC + x
}
main := fn() -> u64 { return f() }