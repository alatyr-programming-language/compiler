## Functions §7.1: a comptime-variadic fn with a LEADING FIXED parameter before the `...`
## rest — `accum(100, 10, 20, 12)` binds `base = 100` normally, then the pack `[10, 20, 12]` is walked by
## `comptime for`, giving 100 + 10 + 20 + 12 = 142. Exercises the fixed-params-plus-pack expansion path.
accum := fn(base : u64, args : ...) -> u64 {
  mut t := base
  comptime for a in args {
    t = t + a
  }
  return t
}

main := fn() -> u64 {
  return accum(100, 10, 20, 12)
}
