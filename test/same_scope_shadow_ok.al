## Issue #414 / Declarations §6.1 — the other half of the shadowing rule, and the part the §6.2
## tightening must NOT touch. Every function here is a shape that stays legal, checked one at a time
## with distinct failure codes from 100 so a regression names itself instead of aliasing a sum:
##
##   reassign        an ordinary `=` write to an existing `mut` binding is not a binding
##   cross_scope     §6.1: an inner block may shadow an enclosing name
##   sibling_blocks  two sequential, non-overlapping blocks may each bind `t`
##   sibling_loops   two sibling `for` loops may each bind `d` (and each its own `i`)
##   arm_payloads    a `match` arm's payload binding may reuse one name across arms
##   late_init       `x : T` with a later `=` initialization is one binding, not two
##   discards        `_` is not a name a second `_` can collide with
##
## The accumulators multiply before adding, so a swapped or dropped contribution changes the result;
## a commutative sum would hide it.
##
## Shadowing a PARAMETER inside a nested block is deliberately NOT here. It is legal under §6.1 and
## `check` accepts it, but the wasm backend traps on it (134) while x86_64, aarch64 and riscv64 all
## answer correctly — an independent, previously unmeasured cross-backend defect, filed as #430.
## Putting it in an over-rejection guard would have made this fixture assert someone else's bug.
Shape := enum { A(u64), B(u64) }

reassign := fn() -> u64 {
  mut x : u64 = 3
  x = 9
  y := 4
  return x * 10 + y
}

cross_scope := fn() -> u64 {
  n := 2
  mut acc : u64 = 0
  if n == 2 {
    n := 7
    acc = acc * 10 + n
  }
  return acc
}

sibling_blocks := fn() -> u64 {
  mut acc : u64 = 0
  if true {
    t := 3
    acc = acc * 10 + t
  }
  if true {
    t := 4
    acc = acc * 10 + t
  }
  return acc
}

sibling_loops := fn() -> u64 {
  mut acc : u64 = 0
  for i in 0..2 {
    d := i + 1
    acc = acc * 10 + d
  }
  for i in 0..2 {
    d := i + 5
    acc = acc * 10 + d
  }
  return acc
}

arm_payloads := fn(s : Shape) -> u64 {
  mut acc : u64 = 0
  match s {
    A(v) => { acc = 100 + v }
    B(v) => { acc = 200 + v }
  }
  return acc
}

late_init := fn() -> u64 {
  mut z : u64 = 0
  z = 6
  return z
}

bump := fn(v : u64) -> u64 { return v + 1 }

discards := fn() -> u64 {
  _ := bump(1)
  _ := bump(2)
  return 5
}

main := fn() -> u64 {
  mut bad : u64 = 0
  if bad == 0 and reassign() != 94 { bad = 100 }
  if bad == 0 and cross_scope() != 7 { bad = 101 }
  if bad == 0 and sibling_blocks() != 34 { bad = 102 }
  if bad == 0 and sibling_loops() != 1256 { bad = 103 }
  if bad == 0 and arm_payloads(Shape.A(1)) != 101 { bad = 104 }
  if bad == 0 and arm_payloads(Shape.B(2)) != 202 { bad = 105 }
  if bad == 0 and late_init() != 6 { bad = 107 }
  if bad == 0 and discards() != 5 { bad = 108 }
  if bad != 0 { return bad }
  return 42
}
