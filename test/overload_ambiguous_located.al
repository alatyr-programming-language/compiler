## FN-7: a bare integer literal matches both integer-scalar overloads, so the call
## has no unique target. Both public `check` and build must reject it as an "ambiguous call" located
## at the call site, rather than accepting check and falling through to an unlocated assembler/link error.
g := fn(x : u64) -> u64 { return 1 }
g := fn(x : i64) -> u64 { return 2 }
main := fn() -> u64 {
  return g(10)
}
