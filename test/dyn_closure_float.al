## e2e (FN-11 — a `dyn fn(…)` fat-pair call with FLOAT user arguments). The `dyn` adapter shifts the
## user arguments down one INTEGER register (freeing %rdi for the environment pointer) and appends the
## captures behind them. An `f64` user argument rides an SSE register instead, which the environment
## pointer never occupies: it must NOT be shifted and must NOT consume an integer slot — otherwise the
## captures land one register too high and the lambda reads an uninitialised one (the closure behaved
## as if its capture were 0). Here `d(v, n)` has ONE float user arg + ONE integer user arg, so exactly
## one integer slot is shifted and the single capture follows it.
## 2.5 + 10 + 3 = 15.5 → 15.
main := fn() -> u64 {
  a := 10
  s1 := fn(x : f64, n : u64) -> f64 { return x + f64(a) + f64(n) }
  d1 : dyn fn(f64, u64) -> f64 = dyn_over(ptr(mut s1))
  v : f64 = 2.5
  return u64(d1(v, 3))
}
