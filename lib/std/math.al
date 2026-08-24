## std::math — f64 numeric functions in pure Alatyr (no libm / no FFI). The `f64` arithmetic and
## comparison operators come from the base tier (`base::num` / `base::cmp`, ambient), so this module is
## just algorithms over them. IEEE-754 semantics (no overflow guard on the float ops themselves).

## |x| — the magnitude. (`0.0 - x` is the float negation; `-x` unary also works.)
pub abs := fn(x : f64) -> f64 { if x < 0.0 { 0.0 - x } else { x } }

## The lesser / greater of two f64 (`fmin`/`fmax` — distinct names, NOT `min`/`max`, so they never
## collide with the ambient generic `base::cmp::min`/`max` on the qualified-tail-name resolution). NaN-
## naive (a NaN operand follows the `<` result); callers needing NaN-aware forms handle it explicitly.
pub fmin := fn(a : f64, b : f64) -> f64 { if a < b { a } else { b } }
pub fmax := fn(a : f64, b : f64) -> f64 { if a < b { b } else { a } }

## floor(x) — the greatest integer <= x, as f64. `i64(x)` truncates TOWARD ZERO; for a negative
## non-integer that overshoots upward, so step down by one. (Values beyond i64 range are out of scope.)
pub floor := fn(x : f64) -> f64 {
  t := i64(x)
  ft := f64(t)
  if ft > x { ft - 1.0 } else { ft }
}

## ceil(x) — the least integer >= x, as f64. Truncation toward zero undershoots for a positive
## non-integer, so step up by one.
pub ceil := fn(x : f64) -> f64 {
  t := i64(x)
  ft := f64(t)
  if ft < x { ft + 1.0 } else { ft }
}

## trunc(x) — toward zero (the raw `i64` conversion, back to f64).
pub trunc := fn(x : f64) -> f64 { f64(i64(x)) }

## sqrt(x) via Newton–Raphson on f(g) = g² - x  (g' = ½(g + x/g)). Converges quadratically; 40 steps
## from the initial guess `x` reach full f64 precision across the practical range. `x <= 0` returns 0
## (0 is exact; a negative input has no real root — 0 is the sentinel, not a trap, so callers guard if
## they must distinguish). Written with `not (0.0 < x)` since the base tier exposes `lt`/`eq` (not `le`).
pub sqrt := fn(x : f64) -> f64 {
  if not (0.0 < x) { return 0.0 }
  mut g : f64 = x
  mut i : u64 = 0
  while i < 40 {
    g = 0.5 * (g + x / g)
    i = i + 1
  }
  g
}

## round(x) — to the NEAREST integer, ties away from zero (round-half-up in magnitude), as f64.
## `floor(x + 0.5)` for x >= 0; the negative side mirrors it so `-2.5 → -3.0` (not `-2.0`).
pub round := fn(x : f64) -> f64 {
  if x < 0.0 { return 0.0 - floor((0.0 - x) + 0.5) }
  floor(x + 0.5)
}

## powi(x, n) — `x` raised to an INTEGER power via binary exponentiation (exact up to f64 rounding;
## no `exp`/`ln`). A negative `n` gives `1 / x^|n|`. `powi(x, 0) == 1.0` (including `0^0`, by convention).
pub powi := fn(x : f64, n : i64) -> f64 {
  mut e : i64 = if n < 0 { 0 - n } else { n }
  mut base : f64 = x
  mut acc : f64 = 1.0
  while e > 0 {
    if (e - (e / 2) * 2) == 1 { acc = acc * base }   ## e is odd → fold in the current base
    base = base * base
    e = e / 2
  }
  if n < 0 { return 1.0 / acc }
  acc
}

## hypot(x, y) — `sqrt(x*x + y*y)`, the Euclidean length (no intermediate-overflow guard — a naive form).
pub hypot := fn(x : f64, y : f64) -> f64 {
  sqrt(x * x + y * y)
}

## exp(x) — e^x. Range-reduce by halving 6 times (r = x/64, so |r| < ~0.08 for |x| <= 5), sum the
## Taylor series on the small `r` (14 terms → remainder far below 1e-15 there), then square 6 times to
## reconstruct exp(r)^64 == exp(x). The reduction keeps every series term small and same-signed, so
## there is no catastrophic cancellation even for negative x. Self-contained (no helper calls) to keep
## the compile-time emit-scratch footprint low. Accurate to ~1e-12 across |x| <= ~5.
pub exp := fn(x : f64) -> f64 {
  r := x / 64.0
  mut term : f64 = 1.0
  mut sum : f64 = 1.0
  mut n : f64 = 1.0
  mut i : u64 = 0
  while i < 14 {
    term = term * r / n
    sum = sum + term
    n = n + 1.0
    i = i + 1
  }
  mut j : u64 = 0
  while j < 6 {
    sum = sum * sum
    j = j + 1
  }
  sum
}

## ln(x) — natural log. Reduce x = m * 2^e with m in [1/sqrt2, sqrt2] by repeated halving/doubling
## (counting e), then ln(m) via the fast atanh series ln(m) = 2*(t + t^3/3 + t^5/5 + …) with
## t = (m-1)/(m+1) (|t| <= 0.172, so 12 terms are ample). Result = e*ln2 + ln(m). `x <= 0` returns 0
## (ln undefined there — sentinel, not a trap; callers guard). `not (0.0 < x)` since the base tier
## exposes lt/eq, not le. Self-contained. Accurate to ~1e-13.
pub ln := fn(x : f64) -> f64 {
  if not (0.0 < x) { return 0.0 }
  mut m : f64 = x
  mut e : f64 = 0.0
  while m >= 1.4142135623730951 {
    m = m * 0.5
    e = e + 1.0
  }
  while m < 0.7071067811865476 {
    m = m * 2.0
    e = e - 1.0
  }
  t := (m - 1.0) / (m + 1.0)
  t2 := t * t
  mut term : f64 = t
  mut sum : f64 = t
  mut k : f64 = 3.0
  mut i : u64 = 0
  while i < 12 {
    term = term * t2
    sum = sum + term / k
    k = k + 2.0
    i = i + 1
  }
  e * 0.6931471805599453 + 2.0 * sum
}

## sin(x) — range-reduce into [-pi, pi] by adding/subtracting 2pi, then the Taylor series (12 odd
## terms, recurrence term *= -r^2/((n)(n+1))). On [-pi, pi] the largest term is ~5.2, so cancellation
## costs at most ~1 digit → still ~1e-14. Self-contained. (Very large |x| reduce slowly but exactly.)
pub sin := fn(x : f64) -> f64 {
  mut r : f64 = x
  while r > 3.141592653589793 { r = r - 6.283185307179586 }
  while r < 0.0 - 3.141592653589793 { r = r + 6.283185307179586 }
  r2 := r * r
  mut term : f64 = r
  mut sum : f64 = r
  mut n : f64 = 2.0
  mut i : u64 = 0
  while i < 12 {
    term = 0.0 - term * r2 / (n * (n + 1.0))
    sum = sum + term
    n = n + 2.0
    i = i + 1
  }
  sum
}

## cos(x) — same range reduction and recurrence as sin, but the series starts at the constant 1.0
## (even powers). Self-contained. Accurate to ~1e-14 on the reduced range.
pub cos := fn(x : f64) -> f64 {
  mut r : f64 = x
  while r > 3.141592653589793 { r = r - 6.283185307179586 }
  while r < 0.0 - 3.141592653589793 { r = r + 6.283185307179586 }
  r2 := r * r
  mut term : f64 = 1.0
  mut sum : f64 = 1.0
  mut n : f64 = 1.0
  mut i : u64 = 0
  while i < 12 {
    term = 0.0 - term * r2 / (n * (n + 1.0))
    sum = sum + term
    n = n + 2.0
    i = i + 1
  }
  sum
}

## PI / TAU — the circle constants as nullary fns (no f64 module-const path in the lib yet; a fn is the
## portable form and folds to a constant at the call site anyway).
pub pi  := fn() -> f64 { 3.141592653589793 }
pub tau := fn() -> f64 { 6.283185307179586 }

## signum(x) — -1.0 / 0.0 / +1.0 by sign (0.0 for exactly 0.0; NaN-naive).
pub signum := fn(x : f64) -> f64 {
  if x < 0.0 { return 0.0 - 1.0 }
  if 0.0 < x { return 1.0 }
  0.0
}

## (no `clamp` here — the ambient `base::cmp::clamp(T, x, lo, hi)` already covers f64, and a same-name
## `std::math::clamp` collides with it on the qualified-tail-name resolution, exactly like `fmin`/`fmax`
## dodge the ambient `min`/`max`.)

## copysign(mag, sign) — |mag| with the sign of `sign` (sign of +0.0 treated as positive; NaN-naive).
pub copysign := fn(mag : f64, sign : f64) -> f64 {
  m := abs(mag)
  if sign < 0.0 { 0.0 - m } else { m }
}

## fract(x) — the fractional part, `x - trunc(x)` (same sign as x; `fract(-2.25) == -0.25`).
pub fract := fn(x : f64) -> f64 { x - trunc(x) }

## to_radians(deg) / to_degrees(rad).
pub to_radians := fn(deg : f64) -> f64 { deg * 3.141592653589793 / 180.0 }
pub to_degrees := fn(rad : f64) -> f64 { rad * 180.0 / 3.141592653589793 }

## cbrt(x) — the real cube root via Newton on g^3 - x (g' = (2g + x/g^2)/3). Handles the sign explicitly
## (Newton on |x|), so a negative input gets the real negative root. `x == 0` returns 0.
pub cbrt := fn(x : f64) -> f64 {
  if x == 0.0 { return 0.0 }
  s := signum(x)
  a := abs(x)
  mut g : f64 = a
  mut i : u64 = 0
  while i < 60 {
    g = (2.0 * g + a / (g * g)) / 3.0
    i = i + 1
  }
  s * g
}
