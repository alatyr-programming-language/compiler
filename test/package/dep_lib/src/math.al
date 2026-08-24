## The dependency's `math` module. Reached from a consumer as `<alias>::math::answer` (Modules §8),
## so under the alias `d` its emitted symbol is `d__math__answer` — NOT the flat `math__answer`.
pub answer := fn() -> u64 {
  return 35
}
