## P1 sema conformance: a return expression must conform to the declared return type.
make := fn() -> str { return "wrong" }

main := fn() -> u64 {
  return make()
}
