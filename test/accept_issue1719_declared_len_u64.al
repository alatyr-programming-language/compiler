## #1719 — the region spec#166's two readings agree on: the program's `len(x : u64)` accepts a `u64`
## local, and no prelude `len` takes one, so the call is the declaration's under shadowing and under
## overloading alike. The refusal of a call the declaration does not accept must not reach this one.
len := fn(x : u64) -> u64 { x }
main := fn() -> u64 {
  n : u64 = 4
  len(n) + 38
}
## expect: run 42
