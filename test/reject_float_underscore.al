## Grammar §2.4 permits `_` between float digits. The parser validates that spelling but rejects it at
## the current backend boundary because FloatLit stores a source span and native `.double` emission
## is verbatim; GAS rejects the underscore. Keep this fixture until the emitter can normalize or emit
## the exact value without losing source spelling.
main := fn() -> u64 {
  x : f64 = 1_0.5
  return u64(x)
}
