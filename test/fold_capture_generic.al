## FN-6 §6.2 — a CAPTURING closure through a GENERIC LOOP HOF (the real map/fold shape). `foldn(T, g,
## x, n)` calls its callable param `g` inside a WHILE loop, accumulating `g(x)` n times — so neither
## the forwarding-inline nor a single-call special case helps; §6.2 MONOMORPHIZES the generic HOF over
## the concrete closure. The driver threads f's capture `k` into every `g(x)` call in the loop body
## (`g(x) -> g(x, k)`) and appends it at the call site (`foldn(u64, f, 20, 2) -> foldn(u64, f, 20, 2,
## k)`); the specialized `foldn` STAYS GENERIC and monomorphizes over T=u64. k := 1, g(20)=21, summed
## twice = 42 — the captured `k` reaches every loop iteration.
foldn := fn(T : type, g : T, x : T, n : usize) -> T {
  mut acc := g(x)
  mut i : usize = 1
  while i < n {
    acc = acc + g(x)
    i = i + 1
  }
  return acc
}
main := fn() -> u64 {
  k := 1
  f := fn(v : u64) -> u64 { return v + k }
  u64(foldn(u64, f, 20, 2))
}
