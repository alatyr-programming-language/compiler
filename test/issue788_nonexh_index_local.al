## Issue #788 / Control Flow §5.1 — a `match` MUST be exhaustive. Scrutinee shape: an ELEMENT of a
## local fixed array `[C; 2]`. `B` is uncovered and no `_` default is present, so this must be refused;
## the parent built it and ran past the `match` to 0 with `xs[0] = C.B`.
C := enum { R, G, B }
main := fn() -> u64 {
  xs : [C; 2] = [C.B, C.G]
  match xs[0] { R => { return 11 }; G => { return 22 } }
  return 0
}
