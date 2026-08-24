## e2e — std::math f64 functions (pure Alatyr, no libm). sqrt is checked via i64(sqrt+0.5) (Newton may
## land 12.0±ε → round); floor/ceil/abs/min/max land exact integers so a direct f64 `==` holds, including
## a NEGATIVE floor (toward -inf, not toward zero). Returns 42 iff every case is exact.
mm := std::math

main := fn() -> u64 {
  s := i64(mm::sqrt(144.0) + 0.5)          ## 12
  s2 := i64(mm::sqrt(2.0) * 1000000.0)     ## 1414213 (sqrt2 = 1.414213562…, *1e6 truncated)
  if s != 12 { return 1 }
  if s2 != 1414213 { return 2 }
  if not (mm::floor(7.9) == 7.0) { return 3 }
  if not (mm::ceil(7.1) == 8.0) { return 4 }
  if not (mm::floor(0.0 - 2.3) == (0.0 - 3.0)) { return 5 }   ## floor toward -inf
  if not (mm::ceil(0.0 - 2.3) == (0.0 - 2.0)) { return 6 }
  if not (mm::abs(0.0 - 9.0) == 9.0) { return 7 }
  if not (mm::fmin(4.0, 6.0) == 4.0) { return 8 }
  if not (mm::fmax(4.0, 6.0) == 6.0) { return 9 }
  if not (mm::trunc(0.0 - 2.9) == (0.0 - 2.0)) { return 10 }  ## toward zero
  if not (mm::round(2.5) == 3.0) { return 15 }
  if not (mm::round(2.4) == 2.0) { return 16 }
  if not (mm::round(0.0 - 2.5) == (0.0 - 3.0)) { return 17 }  ## ties away from zero
  if not (mm::powi(2.0, 10) == 1024.0) { return 18 }
  if not (mm::powi(2.0, 0 - 1) == 0.5) { return 19 }          ## negative exponent
  if not (mm::powi(5.0, 0) == 1.0) { return 20 }
  if not (mm::hypot(3.0, 4.0) == 5.0) { return 21 }
  return 42
}
