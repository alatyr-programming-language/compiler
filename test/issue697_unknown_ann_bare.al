## Issue #697 — a local annotation naming a type that exists nowhere. The parent checked and ran it at
## rc 0: the annotation resolved to nothing and constrained nothing. A parameter spelled the same way was
## already refused; the local slot now is too, at the annotation's line.
main := fn() -> u64 {
  x : NoSuchTypeQQ = 42
  return 42
}
