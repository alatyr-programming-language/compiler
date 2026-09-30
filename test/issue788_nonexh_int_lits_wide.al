## Issue #788 / Control Flow §5.1/§5.4 — a literal-only match over a WIDE integer (a `u64` parameter)
## cannot cover the type's values without a `_`, whatever the literals are.
f := fn(n : u64) -> u64 {
  match n { 0 => { return 11 }; 1 | 2 | 3 => { return 22 } }
  return 0
}
main := fn() -> u64 { return f(7) }
