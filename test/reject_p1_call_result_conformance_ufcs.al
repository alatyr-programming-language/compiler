## P1 sema conformance: the call-result mismatch must also survive UFCS lowering.
V := struct { value : u64 }
S := struct { value : u64 }
make := fn() -> S { return S(value = 1) }
take := fn(receiver : V, text : str) -> u64 { return text.len() }

main := fn() -> u64 {
  receiver := V(value = 1)
  return receiver.take(make())
}
