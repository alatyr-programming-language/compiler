## A SIBLING of `geo` — it reaches `geo`'s `pub` globals only through the qualified path.
pub run := fn() -> u64 {
  geo::G = 6
  geo::G += 1
  geo::TAB[2] = 12
  return geo::G + geo::TAB[2] + u64(geo::MSG.len) + geo::LIMIT + geo::VALUES[1]
}
