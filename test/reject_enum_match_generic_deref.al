## Issue #716 — the pointer arrives as a PARAMETER but the scrutinee is `deref` of a call returning it.
## The parent compared the arms against tag 0 here too and ran to 1 for `G`. Refused now.
C := enum { R, G, B }
gp := fn(p : ptr(mut C)) -> ptr(mut C) { p }
pick := fn(q : ptr(mut C)) -> u64 {
  match deref(gp(q)) { R => { return 10 }; G => { return 42 }; B => { return 30 } }
  return 1
}
main := fn() -> u64 {
  mut x := C.G
  return pick(ptr(mut x))
}
