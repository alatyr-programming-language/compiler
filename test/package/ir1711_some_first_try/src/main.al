## The package `ir1711_some_first_try` (see its `package.al`): `opt.al` declares the Some-first `Option`.
rd := fn(o : Option(ptr(u64))) -> u64 {
  match o { Some(p) => deref(p); None => 7 }
}
fwd := fn(o : Option(ptr(u64))) -> Option(ptr(u64)) {
  p := o?
  Option(ptr(u64)).Some(p)
}
pub main := fn() -> u64 {
  mut x : u64 = 35
  s : Option(ptr(u64)) = Option(ptr(u64)).Some(ptr(x))
  n : Option(ptr(u64)) = Option(ptr(u64)).None
  if rd(fwd(s)) != 35 { return 101 }
  if rd(fwd(n)) != 7 { return 102 }
  return 42
}
