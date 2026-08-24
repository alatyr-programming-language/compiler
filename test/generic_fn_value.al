## e2e (a GENERIC fn with a fn-VALUE param, monomorphized + called indirectly). `g(u64, 41, add1)`
## instantiates `g` for T=u64, passing `add1` (a fn value) as the `f : fn(y:T)->T` param; the body
## `f(x)` is an indirect call through the fn-value. Exercises generic monomorphization + fn-values
## together (the higher-order-generic combo the stdlib's map/filter/reduce rest on). 41 + 1 = 42.
add1 := fn(x : u64) -> u64 { return x + 1 }
g := fn(T : type, x : T, f : fn(y : T) -> T) -> T { return f(x) }
main := fn() -> u64 {
  u64(g(u64, 41, add1))
}
