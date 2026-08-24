## The unselected comptime branch is not resolved or type-checked.
main := fn() -> u64 {
  comptime if compiles(1) { return 42 } else { return no_such_name() }
}
