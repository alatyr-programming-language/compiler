## Issue #716 — the pointer arrives as a PARAMETER but the scrutinee is `deref` of a call returning it.
## Before #716 the legacy x86_64 lowering compared the arms against tag 0 and ran to 1 for `G`; #716 made
## it refuse instead. The program is well-formed (Control Flow §5.1-§5.2, Memory §4.3), and since #1723 the
## shared IR reads the enum type from `gp`'s declared result, so it runs to 42 on x86_64.
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
## expect: run 42
