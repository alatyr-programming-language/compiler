## P1 sema conformance: a struct value is not implicitly a `str` call argument.
S := struct { value : u64 }
take := fn(text : str) -> u64 { return text.len() }

main := fn() -> u64 {
  return take(S(value = 1))
}
