## Issue #304 — an annotated Slice(T) local must enforce T at an element store.
main := fn() -> u64 {
  mut xs : [u64; 2] = [1, 2]
  mut s : Slice(u64) = xs[0..2]
  s[0] = "text"
  0
}
