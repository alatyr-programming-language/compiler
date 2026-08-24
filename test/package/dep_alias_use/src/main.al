## The dependency is reached QUALIFIED through its alias (Modules §8 §4.2): `d::math::answer`.
main := fn() -> u64 {
  return 7 + d::math::answer()
}
