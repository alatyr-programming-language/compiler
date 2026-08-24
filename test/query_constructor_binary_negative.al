## P1-QUERY regression: the constructor value itself is an aggregate, so aggregate + scalar
## is not type-correct. `compiles` must return false without evaluating the operand.
S := struct { a : u64 }

main := fn() -> u64 {
  comptime if compiles(S(a = 1) + 1) { return 1 } else { return 42 }
}
