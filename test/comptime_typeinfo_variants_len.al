## CT (§Comptime 5.1): the SPEC-LITERAL `typeinfo(T).variants.len` nested form — a `comptime for`
## length bound reading an ENUM's VARIANT count from the monomorph instance type. `cnt(Color)`
## unrolls 4× (4 variants) → 4*10 + 2 = 42.
Color := enum { Red, Green, Blue, Yellow }

cnt := fn(T : type) -> u64 {
  mut acc : u64 = 0
  comptime for i in 0..typeinfo(T).variants.len {
    acc = acc + 1
  }
  return acc
}

main := fn() -> u64 {
  return cnt(Color) * 10 + 2
}
