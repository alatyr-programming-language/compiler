## Issue #788 / Control Flow §5.1/§5.4 — the literal-only integer match in VALUE position: the parent
## bound `r` to 0 for `n = 7`, a value no arm covers.
main := fn() -> u64 {
  n : u8 = 7
  r := match n { 0 => { 11 }; 1 => { 22 } }
  return r
}
