## P1 signedness: a §7.2 slice-variadic parameter uses the same runtime slice
## slot shape as `Slice(T)`, so its indexed declared element type must survive
## the signedness scan too. The unsigned case crosses 2^63; the signed control
## proves that `/` and `%` keep the signed path for an `...i64` element.
check_u := fn(xs : ...u64) -> u64 {
  if xs[0] < xs[1] { return 21 }
  return 1
}

check_i := fn(xs : ...i64) -> u64 {
  q := xs[0] / xs[1]
  r := xs[0] % xs[1]
  if q == (0 - 3) {
    if r == (0 - 2) { return 21 }
  }
  return 1
}

main := fn() -> u64 {
  u0 : u64 = 0
  umax : u64 = 18446744073709551615
  i17 : i64 = 0 - 17
  i5 : i64 = 5
  check_u(u0, umax) + check_i(i17, i5)
}
