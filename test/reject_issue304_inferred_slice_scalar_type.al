## Issue #304 — a range-inferred Slice(u64) must enforce u64 at an element store.
main := fn() -> u64 {
  mut xs : [u64; 2] = [1, 2]
  s := xs[0..2]
  s[0] = "text"
  0
}
