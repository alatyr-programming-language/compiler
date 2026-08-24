## e2e — std::random (splitmix64 PRNG). Asserts the three defining properties and returns 42 iff all hold:
##  DETERMINISM: two generators with the same seed produce the same stream.
##  RANGE: next_range(lo, hi) lands in [lo, hi).
##  ADVANCE: consecutive draws differ (the state actually advances).
rng := std::random

main := fn() -> u64 {
  mut a := rng::seeded(12345)
  mut b := rng::seeded(12345)
  det := rng::next_u64(a) == rng::next_u64(b) and rng::next_u64(a) == rng::next_u64(b)

  mut c := rng::seeded(7)
  v := rng::next_range(c, 40, 43)
  inrange := v >= 40 and v < 43

  mut d := rng::seeded(99)
  x := rng::next_u64(d)
  y := rng::next_u64(d)
  advance := x != y

  if det and inrange and advance { return 42 }
  return 7
}
