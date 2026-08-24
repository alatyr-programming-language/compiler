## Focused Grammar §2.4 acceptance fixture: C-style hexadecimal floats.
## `p`/`P` is mandatory; all three mantissa spellings below are normative. This fixture is intended
## for `alatyr check`: native GAS does not accept C-style hex-float text in `.double` yet, so a build
## is deliberately not claimed by this lexer/parser lane.
main := fn() -> u64 {
  a : f64 = 0x1p+0
  b : f64 = 0x1.8p+1
  c : f64 = 0x.8p+1
  d : f64 = 0x1.p+2
  return 42
}
