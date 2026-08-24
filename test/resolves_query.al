## Comptime capability query: declared calls resolve, unknown calls do not.
known := fn() -> u64 { 40 }
pick := fn() -> u64 {
  comptime if resolves(known()) { return 2 } else { return 1 }
}
missing := fn() -> u64 {
  comptime if resolves(no_such_name()) { return 1 } else { return 0 }
}
main := fn() -> u64 { known() + pick() + missing() }
