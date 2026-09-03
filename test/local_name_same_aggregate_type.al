## Issue #406, the ACCEPTED neighbours of the rejected collision — the three same-name shapes the
## x86_64 slot map represents correctly must keep compiling and answering. `widen` binds one name to
## two DISTINCT struct decls that declare the SAME member names (the `CSpan`/`VSpan` shape the
## compiler's own source produces when a same-named callee in another module supplies the recorded
## return type): every field read resolves identically, so the collision guard must stay silent.
## `argopt` binds one name to two instances of ONE generic enum, which share a variant list. `same`
## rebinds one name to its own type in an inner block, the pervasive reuse the flat slot map exists
## for. Each helper reports its own failure code so a wrong answer names the shape that produced it.
Pair := struct { s : usize, n : usize }

Span := struct { s : usize, n : usize }

widen := fn(flag : bool) -> usize {
  if flag {
    p := Pair(s = 1, n = 2)
  }
  p := Span(s = 3, n = 4)
  return p.s * 10 + p.n
}

argopt := fn(flag : bool) -> usize {
  if flag {
    r := Option(u8).Some(3)
  }
  r := Option(usize).Some(9)
  mut out : usize = 120
  match r {
    Some(v) => { out = 20 + v }
    None => { out = 121 }
  }
  return out
}

same := fn(flag : bool) -> usize {
  if flag {
    q := Option(usize).Some(1)
  }
  q := Option(usize).Some(5)
  mut out : usize = 122
  match q {
    Some(v) => { out = 40 + v }
    None => { out = 123 }
  }
  return out
}

main := fn() -> u64 {
  a := widen(true)
  if a != 34 {
    return 110
  }
  b := argopt(true)
  if b != 29 {
    return 111
  }
  c := same(true)
  if c != 45 {
    return 112
  }
  return 42
}
