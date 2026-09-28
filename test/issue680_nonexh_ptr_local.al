## Issue #680 / Control Flow §5.1 — shape 2 of 6: `match deref(p)` where `p` is an UNANNOTATED local
## bound from a call returning `ptr(mut C)` — `parser.al`'s `init_e := p_or(pc)` spelling. The pointee
## was dropped with the rest of the call's type, so the arm list was never checked. `B` is uncovered.
C := enum { R, G, B }
g := fn(k : u64) -> C {
  if k == 0 { return C.R }
  return C.G
}
gp := fn(p : ptr(mut C)) -> ptr(mut C) { p }
main := fn() -> u64 {
  mut c := C.R
  p := gp(ptr(mut c))
  match deref(p) { R => { return 42 }; G => { return 1 } }
  return 2
}
