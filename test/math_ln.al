## e2e — std::math::ln (single transcendental, kept alone to respect the compile-time scratch ceiling).
## Returns 42 iff ln(1)==0 and ln(2)≈0.6931471806 and ln(e)≈1 within 1e-7.
mm := std::math

main := fn() -> u64 {
  eps := 0.0000001
  if not (mm::abs(mm::ln(1.0) - 0.0) < eps) { return 1 }
  if not (mm::abs(mm::ln(2.0) - 0.6931471805599453) < eps) { return 2 }
  if not (mm::abs(mm::ln(2.718281828459045) - 1.0) < eps) { return 3 }
  return 42
}
