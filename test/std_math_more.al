## e2e — the additive std::math batch: pi/tau, signum, clamp, copysign, fract, to_radians/to_degrees, cbrt.
## Each lands an exact (or round-to-exact) value so a direct f64 `==` / i64 round holds. Returns 42 iff all.
mm := std::math

main := fn() -> u64 {
  ## circle constants (folded via the nullary fns) — check to 6 digits after scaling.
  if i64(mm::pi() * 1000000.0) != 3141592 { return 1 }
  if i64(mm::tau() * 1000000.0) != 6283185 { return 2 }

  ## signum: -1 / 0 / +1.
  if not (mm::signum(0.0 - 3.0) == (0.0 - 1.0)) { return 3 }
  if not (mm::signum(5.0) == 1.0) { return 4 }
  if not (mm::signum(0.0) == 0.0) { return 5 }

  ## copysign: magnitude of a, sign of b.
  if not (mm::copysign(4.0, 0.0 - 2.0) == (0.0 - 4.0)) { return 9 }
  if not (mm::copysign(0.0 - 4.0, 2.0) == 4.0) { return 10 }

  ## fract: fractional part, sign-preserving.
  if not (mm::fract(2.25) == 0.25) { return 11 }
  if not (mm::fract(0.0 - 2.25) == (0.0 - 0.25)) { return 12 }

  ## angle conversions: 180° == π rad, and back.
  if i64(mm::to_radians(180.0) * 1000000.0) != 3141592 { return 13 }
  if i64(mm::to_degrees(mm::pi()) + 0.5) != 180 { return 14 }

  ## cbrt: real cube root, incl. the negative branch.
  if i64(mm::cbrt(27.0) + 0.5) != 3 { return 15 }
  if i64(mm::cbrt(0.0 - 64.0) - 0.5) != (0 - 4) { return 16 }   ## cbrt(-64) = -4  ((-4)^3 = -64)
  if not (mm::cbrt(0.0) == 0.0) { return 17 }

  return 42
}
