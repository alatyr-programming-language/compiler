## Comptime capability query: a resolvable expression is true and unresolved names are false.
pick := fn() -> u64 {
  comptime if compiles(1) { return 40 } else { return 1 }
}
missing := fn() -> u64 {
  comptime if compiles(no_such_name()) { return 1 } else { return 1 }
}
missing_var := fn() -> u64 {
  comptime if compiles(no_such_local) { return 1 } else { return 0 }
}
main := fn() -> u64 { pick() + missing() + missing_var() }
