## §8.1 — a failing named f64 validity predicate must trap at the explicit constructor.
is_nonzero := fn(v : f64) -> bool { return v != 0.0 }
NonZero := @require(is_nonzero) f64

main := fn() -> u64 {
  x := NonZero(0.0)
  return 42
}
