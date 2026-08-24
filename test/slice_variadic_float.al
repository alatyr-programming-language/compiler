## Functions §7.2: a SLICE variadic with a FLOAT element `rest : ...f64` — the trailing call args
## are gathered into ONE runtime `[f64]` slice (each arg's IEEE-754 bits stored as one word by the
## call-site gather), and the callee reads them like any `Slice(f64)` param (`for x in rest`). The
## param binds `eek == 9` so the loop var is a float local and `s + x` uses the xmm add path.
## fsum(1.5, 2.5, 38.0) = 42.0 -> u64 = 42. x86_64 only (the call-site gather is x86-only for now).
fsum := fn(xs : ...f64) -> f64 {
  mut s : f64 = 0.0
  for x in xs {
    s = s + x
  }
  return s
}
main := fn() -> u64 {
  return u64(fsum(1.5, 2.5, 38.0))
}
