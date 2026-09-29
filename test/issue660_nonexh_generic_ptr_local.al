## Issue #660 / Control Flow §5.1 — a value local bound from `deref` of a GENERIC call whose result is
## `ptr(mut T)` (`x := deref(id(C, ptr(mut c)))`). The pointee is the type argument at T's position;
## before this it was unknown, so the `match` below — `B` uncovered, no `_` — built and ran on the parent.
C := enum { R, G, B }
id := fn(T : type, p : ptr(mut T)) -> ptr(mut T) { p }
main := fn() -> u64 {
  mut c := C.R
  x := deref(id(C, ptr(mut c)))
  match x { R => { return 42 }; G => { return 1 } }
  return 2
}
