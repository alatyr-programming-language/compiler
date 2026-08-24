## P1-QUERY / sema parity: the same invalid aggregate + scalar expression must be rejected
## outside a capability query rather than lowered as a word-zero arithmetic result.
S := struct { a : u64 }

main := fn() -> u64 {
  return S(a = 1) + 1
}
