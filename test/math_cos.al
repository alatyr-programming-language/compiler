## e2e — std::math::cos (single transcendental, kept alone to respect the compile-time scratch ceiling).
## Returns 42 iff cos(0)==1 and cos(pi/2)≈0 and cos(pi)≈-1 within 1e-7.
mm := std::math

main := fn() -> u64 {
  eps := 0.0000001
  if not (mm::abs(mm::cos(0.0) - 1.0) < eps) { return 1 }
  if not (mm::abs(mm::cos(1.5707963267948966) - 0.0) < eps) { return 2 }
  if not (mm::abs(mm::cos(3.141592653589793) - (0.0 - 1.0)) < eps) { return 3 }
  return 42
}
