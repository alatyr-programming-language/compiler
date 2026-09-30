## Issue #788 / Control Flow §5.4 — ranges must cover the WHOLE width of the scrutinee's type. For
## `i8` the arms below leave -128 uncovered, and no `_` default is present.
main := fn() -> u64 {
  n : i8 = 5
  r := match n { -127..=-1 => { 1 }; 0..=127 => { 42 } }
  return r
}
