## P1 sema conformance: a UFCS call result must conform at a return boundary too.
V := struct { value : u64 }
text := fn(receiver : V) -> str { return "wrong" }

main := fn() -> u64 {
  receiver := V(value = 1)
  return receiver.text()
}
