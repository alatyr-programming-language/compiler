## Issue #788 / Control Flow §5.1/§5.4 — an integer scrutinee needs a `_` or ranges covering its whole
## width. `n : u8` with only the literal arms 0 and 1 leaves 2..=255 uncovered; the parent skipped it.
main := fn() -> u64 {
  n : u8 = 7
  match n { 0 => { return 11 }; 1 => { return 22 } }
  return 0
}
