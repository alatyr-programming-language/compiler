## P1 sema conformance: a struct-returning call is not a `str` argument.
S := struct { value : u64 }
make := fn() -> S { return S(value = 1) }
take := fn(text : str) -> u64 { return text.len() }

main := fn() -> u64 {
  return take(make())
}
