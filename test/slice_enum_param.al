## CG-6 / Slice(T) params: an enum-element Slice(E) parameter is a pointer to the
## caller's {ptr,len} block, and `match s[i]` must materialize the enum element words.
E := enum { A(u64), B }

sum := fn(s : Slice(E)) -> u64 {
  mut acc : u64 = 0
  for i in 0..2 {
    match s[i] {
      E::A(x) => { acc = acc + x }
      E::B => {}
    }
  }
  return acc
}

main := fn() -> u64 {
  es := [E.A(40), E.A(2)]
  s := es[0..2]
  return sum(es[0..2]) + sum(s) - 42
}
