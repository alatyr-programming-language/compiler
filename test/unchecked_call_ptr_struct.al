## #1139 — a struct whose first field is a pointer, returned under the grant
## `unchecked mk(ptr(mut buf[0]), 40)` (the shape of the stdlib's `unchecked arena_over(...)`).
## Expected exit 42.
Rec := struct { p : ptr(mut u8), n : usize, k : usize }
mk := fn(p : ptr(mut u8), n : usize) -> Rec { Rec(p = p, n = n, k = 2) }
main := fn() -> u64 {
  mut buf : [u8; 8] = [0, 0, 0, 0, 0, 0, 0, 0]
  r := unchecked mk(ptr(mut buf[0]), 40)
  u64(r.n + r.k)
}
