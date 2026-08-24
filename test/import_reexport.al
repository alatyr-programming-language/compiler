## P1 ordinary namespace resolution: one public module re-export crosses the existing resolver.
## The module directives keep both modules in one focused non-x86 front-end input; the semantic
## shape is the spec form `pub math := std::math`, then `facade::math::floor(…)`.
module facade
pub math := std::math

module import_reexport
main := fn() -> u64 {
  if facade::math::floor(7.9) == 7.0 { return 42 }
  return 1
}
