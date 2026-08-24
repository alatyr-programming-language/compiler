## Functions §7.2: a SLICE variadic `rest : ...T` with a LEADING FIXED parameter before it
## (`fn(base : A, rest : ...T)`) — the common `join(sep, ...parts)` / builder shape. The call site
## evaluates the fixed args into argreg(0..nfixed-1), gathers the trailing args into a `{ptr, len}`
## slice in argreg(nfixed), then calls. The body seeds the accumulator with the fixed `base` and sums
## the slice: base=2, then 10+20+10 = 42.
sumfrom := fn(base : u64, xs : ...u64) -> u64 {
  mut s : u64 = base
  for x in xs {
    s = s + x
  }
  return s
}
main := fn() -> u64 {
  return sumfrom(2, 10, 20, 10)
}
