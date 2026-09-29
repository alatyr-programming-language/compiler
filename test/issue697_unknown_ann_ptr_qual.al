## Issue #697 — a path-qualified pointee whose last segment names no type anywhere (the issue's T1 row).
main := fn() -> u64 {
  mut y := 1
  p : ptr(mod_zz::NoSuchTypeQQ) = ptr(mut y)
  return 42
}
