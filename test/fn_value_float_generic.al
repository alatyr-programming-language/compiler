## e2e (FN-6 — a float fn value through a GENERIC higher-order fn). `twice(T, f, x)` takes its mapper
## as a fn value typed `fn(T) -> T` and calls it indirectly TWICE; the instance is monomorphized at
## `T = f64`. Two distinct classifications meet here, and both were missing:
##   * inside the instance, `f(x)` is an indirect call whose return type is the type PARAMETER `T` —
##     resolved by substituting the instance's type argument (`T` → `f64`);
##   * at the call site, `twice`'s declared return is also `T`, so `u64(twice(f64, …))` has to know
##     the call yields a float — otherwise it read the IEEE bits as an integer and produced 0.
## The instance itself carries the value in the ordinary word-sized (bits-in-%rax) convention, so only
## the classification changes, not the calling convention. addf(addf(10.0)) = 12.0 → 12.
twice := fn(T : type, f : fn(T) -> T, x : T) -> T { return f(f(x)) }
addf := fn(x : f64) -> f64 { return x + 1.0 }

main := fn() -> u64 {
  return u64(twice(f64, addf, 10.0))
}
