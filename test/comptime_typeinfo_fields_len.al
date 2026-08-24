## CT (§Comptime 5.1): the SPEC-LITERAL `typeinfo(T).fields.len` nested form — a `comptime for`
## length bound reading the field count of the monomorph instance type, the same value the lean
## `.n`/`.len` shorthand yields. `cnt(S)` unrolls 3× (3 fields) → 3*14 = 42.
S := struct { a : u64, b : u64, c : u64 }

cnt := fn(T : type) -> u64 {
  mut acc : u64 = 0
  comptime for i in 0..typeinfo(T).fields.len {
    acc = acc + 1
  }
  return acc
}

main := fn() -> u64 {
  return cnt(S) * 14
}
