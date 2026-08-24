## A type-mismatched operand is false for compiles, without rejecting the query itself.
takes_str := fn(s : str) -> u64 { 42 }
main := fn() -> u64 {
  comptime if compiles(takes_str(1)) { return 1 } else { return 42 }
}
