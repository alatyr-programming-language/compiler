## e2e — std::math::sin (single transcendental, kept alone to respect the compile-time scratch ceiling).
## Returns 42 iff sin(0)==0 and sin(pi/2)≈1 and sin(pi)≈0 within 1e-7.
mm := std::math

main := fn() -> u64 {
  eps := 0.0000001
  if not (mm::abs(mm::sin(0.0) - 0.0) < eps) { return 1 }
  if not (mm::abs(mm::sin(1.5707963267948966) - 1.0) < eps) { return 2 }
  if not (mm::abs(mm::sin(3.141592653589793) - 0.0) < eps) { return 3 }
  return 42
}
