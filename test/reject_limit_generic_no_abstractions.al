## CG-12 / FND-10: a generic definition's trailing expression is still part of
## this translation unit and cannot hide a structured abstraction.
@limits(no_abstractions)
identity := fn(T : type, x : T) -> T {
  x + x
}
main := fn() -> u64 { return 0 }
