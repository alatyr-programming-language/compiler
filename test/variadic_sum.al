## Functions §7.1: a comptime-VARIADIC fn `fn(args : ...)` collects its trailing arguments
## into a comptime pack that the body walks with `comptime for` — monomorphized and expanded at the call
## site (no runtime fn). `sum(10, 20, 12)` unrolls to `total += 10; += 20; += 12` = 42.
sum := fn(args : ...) -> u64 {
  mut total := 0
  comptime for a in args {
    total = total + a
  }
  return total
}

main := fn() -> u64 {
  return sum(10, 20, 12)
}
