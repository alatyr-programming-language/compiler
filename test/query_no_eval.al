## Query operands are compile-time inspected and must never execute at runtime.
side := fn() -> u64 { panic("query operand evaluated") }
main := fn() -> u64 {
  comptime if compiles(side()) { return 42 } else { return 7 }
}
