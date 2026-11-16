## The package `ir1711_some_first_u64` (see its `package.al`): `opt.al` declares the Some-first `Option`.
mk := fn(v : u64, z : u64) -> Option(u64) {
  if z == 0 { return Option(u64).None }
  Option(u64).Some(v)
}
rd := fn(o : Option(u64)) -> u64 {
  match o { Some(v) => v + 1; None => 7 }
}
rd_none_first := fn(o : Option(u64)) -> u64 {
  match o { None => 7; Some(v) => v + 1 }
}
pub main := fn() -> u64 {
  if rd(mk(0, 1)) != 1 { return 101 }
  if rd(mk(40, 1)) != 41 { return 102 }
  if rd(mk(40, 0)) != 7 { return 103 }
  z : Option(u64) = mk(0, 1)
  if rd_none_first(z) != 1 { return 104 }
  n : Option(u64) = Option(u64).None
  if rd_none_first(n) != 7 { return 105 }
  return 42
}
