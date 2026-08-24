## e2e (Types §9.4 — a RANGE-SLICE expression returned BY VALUE from a `-> Slice(T)` fn).
## `emit_struct_value` had no `Expr::Slice` arm, so `return xs[0..4]` fell to its `_` default and left
## the 2-word return convention (ptr/%rax, len/%rdx) UNTOUCHED: the caller's `r.len` / `r[i]` read
## stale registers — in practice 0 — a SILENT MISCOMPILE. The sibling spellings both worked
## (`return Slice(u64)(ptr = …, len = …)`, and `return s` for a slice PARAM), so they disagreed.
## The pair now comes from the same `emit_slice_pair` choke point every view value flows through,
## which is also where a range slice over a raw ARRAY takes the stride-aware element-0 ADDRESS
## instead of the str byte-view reading.
## Value: 4 + 2 + 30 = 36 (< 126 — the WASM sweep's WASI `proc_exit` bound).
mk := fn(in xs : [u64; 4]) -> Slice(u64) { return xs[0..4] }
mid := fn(in xs : [u64; 4]) -> Slice(u64) { return xs[1..3] }   ## a non-zero `lo` — ptr = elem0 + lo*8

main := fn() -> u64 {
  a := [10, 20, 30, 40]
  r := mk(a)
  m := mid(a)
  if r.len != 4 { return 1 }        ## was 0
  if r[0] != 10 { return 2 }
  if r[3] != 40 { return 3 }
  if m.len != 2 { return 4 }
  if m[0] != 20 { return 5 }
  return u64(r.len) + u64(m.len) + u64(m[1])
}
