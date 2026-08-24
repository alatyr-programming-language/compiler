## A `mut` binding carries the same assignability rule as a plain one (Declarations §3.1).
main := fn() -> u64 {
  mut x : usize = "nope"
  return u64(x)
}
