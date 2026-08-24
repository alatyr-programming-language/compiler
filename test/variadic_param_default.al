## FN-5 + Functions §7.1: a comptime-variadic callee may default an omitted trailing FIXED
## parameter before the `...` rest when the pack is empty. `accum()` supplies `base = 40`, then walks no
## pack entries; the explicit call keeps proving the fixed-param path.
accum := fn(base : u64 = 40, args : ...) -> u64 {
  mut total := base
  comptime for a in args {
    total = total + a
  }
  return total
}

main := fn() -> u64 {
  accum(2) + accum()
}
