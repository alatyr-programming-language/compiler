## CT (§Comptime 5.1): `typeinfo(T).n` is the comptime MEMBER COUNT of the monomorph instance type,
## usable as a `comptime for` length bound (derive's index folds). STRUCT → field count, TUPLE →
## component count (ARRAY → element count already worked). `cnt(S)` unrolls 3× (3 fields), `cnt((…×4))`
## unrolls 4× (4 components): 3*10 + 4 = 34.
S := struct { a : u64, b : u64, c : u64 }

cnt := fn(T : type) -> u64 {
  mut acc : u64 = 0
  comptime for i in 0..typeinfo(T).n {
    acc = acc + 1
  }
  return acc
}

main := fn() -> u64 {
  return cnt(S) * 10 + cnt((u64, u64, u64, u64))
}
