## #1719 — the program's `len` takes an ARRAY, and the call passes one: the declaration accepts it, so
## the call is the declaration's (the region spec#166's readings agree on, a concrete override of the
## prelude's generic `len`). An array parameter records its element type, `u64`, as its type span; the
## refusal of a call the declaration does not accept read that as a scalar parameter and refused this
## valid program in its first draft. It answers 42, as on the parent 263da9f6 and on #1434's head.
len := fn(xs : [u64; 4]) -> u64 { xs[0] + 41 }
main := fn() -> u64 {
  xs : [u64; 4] = [1, 2, 3, 4]
  len(xs)
}
## expect: run 42
