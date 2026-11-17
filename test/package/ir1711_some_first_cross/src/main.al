## Part of the package `ir1711_some_first_cross` (see its `package.al`); `opt.al` declares the
## Some-first `Option`.
rd := fn(o : Option(ptr(u64))) -> u64 {
  match o { Some(p) => deref(p); None => 7 }
}
rd_none_first := fn(o : Option(ptr(u64))) -> u64 {
  match o { None => 7; Some(p) => deref(p) }
}
mk := fn(p : ptr(u64), z : u64) -> Option(ptr(u64)) {
  if z == 0 { return Option(ptr(u64)).None }
  Option(ptr(u64)).Some(p)
}
lg_rd := fn(o : Option(ptr(u64))) -> u64 {
  w := 1.5
  match o { Some(p) => deref(p); None => 7 }
}
lg_pass := fn(x : ptr(u64)) -> u64 {
  w := 2.5
  return rd(mk(x, 1)) + rd(mk(x, 0))
}
pub main := fn() -> u64 {
  mut x : u64 = 35
  if rd(mk(ptr(x), 1)) != 35 { return 101 }
  if rd(mk(ptr(x), 0)) != 7 { return 102 }
  s : Option(ptr(u64)) = mk(ptr(x), 1)
  if rd_none_first(s) != 35 { return 103 }
  n : Option(ptr(u64)) = Option(ptr(u64)).None
  if rd_none_first(n) != 7 { return 104 }
  if lg_rd(mk(ptr(x), 1)) != 35 { return 105 }
  if lg_rd(Option(ptr(u64)).None) != 7 { return 106 }
  if lg_pass(ptr(x)) != 42 { return 107 }
  return 42
}
## Compiled alone (the corpus walk), this file is a bare program over the prelude's `None`-first
## `Option`, the same folded word in the other variant order. As in the package, wasm is left
## undeclared (its legacy emitter traps on a folded local).
## expect(x86_64): run 42
## expect(aarch64): run 42
## expect(riscv64): run 42
