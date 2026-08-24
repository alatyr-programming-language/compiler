## e2e — std::math::sqrt (Newton iteration, already present). Kept as its own tiny program alongside the
## transcendentals. Returns 42 iff sqrt(144)≈12 and sqrt(2)≈1.4142135624 and sqrt(0)==0 within 1e-7.
mm := std::math

main := fn() -> u64 {
  eps := 0.0000001
  if not (mm::abs(mm::sqrt(144.0) - 12.0) < eps) { return 1 }
  if not (mm::abs(mm::sqrt(2.0) - 1.4142135623730951) < eps) { return 2 }
  if not (mm::abs(mm::sqrt(0.0) - 0.0) < eps) { return 3 }
  return 42
}
