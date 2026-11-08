## Issue #1502 / Declarations §5 + §6.1 — a local declared INSIDE a nested block of one function, with the
## name of a module constant, is a distinct binding whose scope is that block (§5, §6.1). It must not
## touch the constant, so a read of the constant in ANOTHER function, after the first one has run,
## still answers the constant's value.
##
## On aarch64 and riscv64 it did not. Their legacy statement emitters resolve a declared name to a module
## data binding's `.data` label BEFORE any frame slot, and a declaration inside a nested block has no
## frame slot of its own there (the local scan walks the function's top-level statements only). So
## `if t == 1 { K1 := 50 ... }` stored 50 into `K1`'s own cell, and every later legacy read of `K1`
## anywhere answered the dead local. wasm has the same shape through `global.set $K1`. The parent answered
## 5 (case 1, class 1) on all three; x86_64 answered 99.
##
## Every case is CLASSIFIED: class 0 is right, class 1 is the dead local's value, class 2 anything else.
## The exit code is `4 * case + class` of the FIRST failing case, 99 when all hold; all are below 126.
##
## 1  the issue's reproducer: an untyped scalar constant, the local in an `if` block of `g1`, the
##    constant read in `h1` after `g1` ran.
## 2  a TYPED scalar constant. A read through the shared IR folds it to its initializer and so hid the
##    overwritten cell; `h2`'s own block-local declaration (never executed) keeps it on the legacy path,
##    where the read loads the cell.
## 3  the declaration in a `while` body.
## Each in-block read must still answer the local's own value; that is checked first, as class 2.
##
## The fix is fail-loud, not lexical scoping: those emitters now trap on such a declaration (a stub,
## `brk #0` / `ebreak` / `unreachable`) instead of storing. aarch64, riscv64 and wasm therefore trap
## here, as known deviations under #1502, until a block-local declaration gets a slot of its own.
## spec: Declarations §5, §6.1

K1 := 7
g1 := fn(t : u64) -> u64 {
  if t == 1 { K1 := 50 ; x : u64 = K1 ; return x }
  return 0
}
h1 := fn() -> u64 { a : u64 = K1 ; return a }

K2 : u64 = 11
g2 := fn(t : u64) -> u64 {
  if t == 1 { K2 := 54 ; x : u64 = K2 ; return x }
  return 0
}
h2 := fn(t : u64) -> u64 {
  a : u64 = K2
  if t == 0 { K2 := 9 ; y : u64 = K2 ; return y }
  return a
}

K3 := 13
g3 := fn(n : u64) -> u64 {
  mut i : u64 = 0
  mut r : u64 = 0
  while i < n { K3 := 58 ; r = K3 ; i += 1 }
  return r
}
h3 := fn() -> u64 { a : u64 = K3 ; return a }

classify := fn(got : u64, want : u64, dead : u64) -> u64 {
  if got == want { return 0 }
  if got == dead { return 1 }
  2
}

main := fn() -> u64 {
  if g1(1) != 50 { return 6 }
  k1 := classify(h1(), 7, 50)
  if k1 != 0 { return 4 + k1 }
  if g2(1) != 54 { return 10 }
  k2 := classify(h2(1), 11, 54)
  if k2 != 0 { return 8 + k2 }
  if g3(1) != 58 { return 14 }
  k3 := classify(h3(), 13, 58)
  if k3 != 0 { return 12 + k3 }
  99
}
## expect: run 99
