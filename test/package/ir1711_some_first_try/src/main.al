## Part of the package `ir1711_some_first_try` (see its `package.al`); `opt.al` declares the
## Some-first `Option`.
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
## Compiled alone (the corpus walk), this file is a bare program over the prelude's `None`-first
## `Option`, the same folded word in the other variant order. As in `test/ir_option_ptr_try.al`,
## only x86_64 is declared: the twins' legacy emitter traps on `?` over a folded option, and wasm on
## a folded local.
## expect(x86_64): run 42
