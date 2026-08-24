## e2e: the f64 SysV ABI — float params arrive in xmm0.., an f64 return is delivered in xmm0, and a
## float param counts INDEPENDENTLY of an integer param (so `mix` takes n in %rdi, x in %xmm0).
## Expected process exit: 17.
##   scale(2.5, 4.0) = 10.0          (two float params, float return)
##   addf(10.0, 1.5) = 11.5  -> 11   (float param fed from another float-returning call)
##   mix(3, 2.0)     = 2.0 * 3 = 6.0 -> 6   (mixed int+float params, f64(n) int→float inside)
##   total                            = 17
scale := fn(x : f64, k : f64) -> f64 {
  return x * k
}
addf := fn(a : f64, b : f64) -> f64 {
  return a + b
}
mix := fn(n : u64, x : f64) -> f64 {
  return x * f64(n)
}
main := fn() -> u64 {
  r : f64 = scale(2.5, 4.0)
  s : f64 = addf(r, 1.5)
  m : f64 = mix(3, 2.0)
  return u64(s) + u64(m)
}
