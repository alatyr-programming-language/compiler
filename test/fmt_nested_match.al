## fmt — a value-`match` NESTED as another match arm's body round-trips (§5 tooling). Each arm value is
## an expression, so an inner `match` renders inline inside the outer arm; enum-variant and integer-
## literal patterns + the `_` wildcard all survive. c=Green, d=2:
##   v: Green arm → match d { _ => 7 } = 7 ; w: d default arm → match c { _ => 30 } = 30 ; 7 + 30 = 37.
Color := enum { Red, Green, Blue }
main := fn() -> u64 {
  c := Color.Green
  d := 2
  v := match c {
    Red => 1,
    Green => match d { 0 => 5, 1 => 6, _ => 7 },
    Blue => 3,
  }
  w := match d {
    0 => 10,
    _ => match c { Red => 20, _ => 30 },
  }
  return v + w
}
