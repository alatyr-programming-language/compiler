## Issue #697 — the same unknown name as the POINTEE of a `ptr(…)` annotation (the issue's T2 row).
main := fn() -> u64 {
  mut y := 1
  p : ptr(NoSuchTypeQQ) = ptr(mut y)
  return 42
}
