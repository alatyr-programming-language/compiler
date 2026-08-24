## e2e — std::math::exp (single transcendental, kept alone to respect the compile-time scratch ceiling).
## Returns 42 iff exp(0)==1 and exp(1)≈e and exp(-2)≈0.1353352832 within 1e-7.
mm := std::math

main := fn() -> u64 {
  eps := 0.0000001
  if not (mm::abs(mm::exp(0.0) - 1.0) < eps) { return 1 }
  if not (mm::abs(mm::exp(1.0) - 2.718281828459045) < eps) { return 2 }
  if not (mm::abs(mm::exp(0.0 - 2.0) - 0.1353352832366127) < eps) { return 3 }
  return 42
}
