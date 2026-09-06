## Issue #414 / Declarations §6.2 — the annotated declaration form `name : T = v` is a binding too,
## so a second one of the same name in the same list is the same error. Written with `mut` on both
## halves, which is the shape most easily mistaken for an ordinary write: a `mut` binding is writable
## with `=`, and that is what the second line should have used.
run := fn() -> u64 {
  mut n : u64 = 4
  mut n : u64 = 6
  return n
}

main := fn() -> u64 { return run() }
