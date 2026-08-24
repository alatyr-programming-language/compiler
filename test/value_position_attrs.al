## Regression for value-position declaration attributes (Declarations §2.3):
## `@export` and `@inline` decorate the fn value after `:=`, not the binding prefix.
## The export is checked by the native/WAT symbol probes; the inline helper must be
## substituted at its direct call site rather than emitted as a call.
exported := @export("value_export") fn() -> u64 {
  return add(20, 22)
}

add := @inline fn(a : u64, b : u64) -> u64 {
  return a + b
}

main := fn() -> u64 {
  return exported()
}
