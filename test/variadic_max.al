## ROADMAP §3 / Functions §7.1: a comptime-variadic body with CONTROL FLOW in the unrolled loop — each
## `comptime for` iteration emits the `if v > m { m = v }` body with `v` bound to the pack element.
## maxof(3, 42, 7, 20) = 42. Also exercises a leading fixed param (`first`) + a scalar pack.
maxof := fn(first : u64, rest : ...) -> u64 {
  mut m := first
  comptime for v in rest {
    if v > m {
      m = v
    }
  }
  return m
}

main := fn() -> u64 {
  return maxof(3, 42, 7, 20)
}
