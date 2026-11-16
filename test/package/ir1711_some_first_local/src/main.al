## The package `ir1711_some_first_local` (see its `package.al`): `opt.al` declares the Some-first `Option`.
pub main := fn() -> u64 {
  mut x : u64 = 8
  s : Option(ptr(u64)) = Option(ptr(u64)).Some(ptr(x))
  match s { Some(p) => { if deref(p) != 8 { return 101 } } None => { return 102 } }
  match s { None => { return 103 } Some(p) => { if deref(p) != 8 { return 104 } } }
  mut t : Option(ptr(u64)) = s
  t = Option(ptr(u64)).None
  mut seen : u64 = 0
  match t { Some(p) => { if deref(p) != 0 { return 105 } } None => { seen = seen + 1 } }
  match t { None => { seen = seen + 1 } Some(p) => { return 106 } }
  if seen != 2 { return 107 }
  if deref(ptr(x)) != 8 { return 108 }
  return 42
}
