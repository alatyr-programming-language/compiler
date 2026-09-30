## Issue #788 / Control Flow §5.1 — scrutinee shape: an ELEMENT of a by-value PARAMETER `[C; 2]`.
## `B` is uncovered and no `_` default is present, so this must be refused; the parent built it and
## skipped the `match` for `xs[1] = C.B`.
C := enum { R, G, B }
f := fn(xs : [C; 2]) -> u64 {
  match xs[1] { R => { return 11 }; G => { return 22 } }
  return 0
}
main := fn() -> u64 { return f([C.R, C.B]) }
