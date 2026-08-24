## FN-6 §6.2 — a CAPTURING closure through a GENERIC LOOP HOF (`foldn`, the real map/fold shape:
## it calls its callable `g` inside a WHILE loop) that is called at TWO sites — once with a
## capturing closure `f` (captures `k`), once with a NON-capturing top-level `dbl`. The driver
## deep-CLONES `foldn` for the capturing site, threading f's capture `k` into every `g(x)` in the
## loop body (`g(x) -> g(x, k)`); the original generic `foldn` stays intact for the `dbl` site. Both
## the clone and the original monomorphize over T=u64. This is the functional-programming unlock:
## a captured local reaching every loop iteration of a generic HOF used at more than one call site.
## k := 1: foldn(clone, f, 10, 2) = (10+1)+(10+1) = 22; foldn(orig, dbl, 5, 2) = (5*2)+(5*2) = 20; 42.
foldn := fn(T : type, g : T, x : T, n : usize) -> T {
  mut acc := g(x)
  mut i : usize = 1
  while i < n {
    acc = acc + g(x)
    i = i + 1
  }
  return acc
}
dbl := fn(v : u64) -> u64 { return v * 2 }
main := fn() -> u64 {
  k := 1
  f := fn(v : u64) -> u64 { return v + k }
  a := foldn(u64, f, 10, 2)
  b := foldn(u64, dbl, 5, 2)
  u64(a + b)
}
