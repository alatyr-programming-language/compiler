## P1 sema conformance: the same aggregate-to-str mismatch through UFCS.
V := struct { value : u64 }
S := struct { value : u64 }
take := fn(receiver : V, text : str) -> u64 { return text.len() }

main := fn() -> u64 {
  receiver := V(value = 1)
  return receiver.take(S(value = 2))
}
