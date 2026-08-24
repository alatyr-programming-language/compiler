## Functions §7.2: a HOMOGENEOUS SLICE variadic `name : ...T` — a trailing rest WITH a concrete
## element type gathers the call's trailing arguments into ONE runtime `[T]` slice the callee reads
## like any `Slice(T)` param (`for x in xs`, `xs[i]`, `xs.len()`). The call site gathers `10, 20, 12`
## into a contiguous block + passes a `{ptr, len}` slice; the body sums it = 42.
sum := fn(xs : ...u64) -> u64 {
  mut s : u64 = 0
  for x in xs {
    s = s + x
  }
  return s
}
main := fn() -> u64 {
  return sum(10, 20, 12)
}
