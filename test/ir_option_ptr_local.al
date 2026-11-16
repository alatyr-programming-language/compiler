## e2e — #1576 (IR-19): a NICHE-FOLDED `Option(ptr(T))` LOCAL is built by the shared IR in every
## form, and its `match` reads the one word against 0 instead of a discriminant (Types §6.2/§8,
## Memory §4.2). The absent case WRITES the null pattern: a local that answered `Some` and is
## re-assigned `None` must answer `None` after it, never the pointer the earlier `Some` left behind.
## On the parent every function here was refused (`CSigParamUnresolved`, `CSigResultWide`), and the
## legacy emitter that took them over answers 42 here on x86_64, aarch64 and riscv64 and traps (134)
## on wasm, where a folded LOCAL is what its emitter cannot do.
## 42 when every form held; otherwise 100 + the mask of the failed ones.
## The directive is x86_64-only, as it is for the whole folded-option family: aarch64, riscv64 and wasm
## keep a signature that mentions a folded option on the legacy emitter (`ir::sig_has_folded_option`,
## refused in `sa_fn`/`sr_fn`/`sw_fn` and in each `*_call`, because THEIR legacy emitter passes an
## aggregate as the unfolded tag and payload words). This slice moves no value on those three targets:
## measured after it, aarch64 and riscv64 still answer 42 and wasm still traps 134, byte for byte what
## the parent answered.
rd := fn(o : Option(ptr(u64))) -> u64 {
  match o { Some(p) => deref(p); None => 7 }
}
mk := fn(z : u64, p : ptr(u64)) -> Option(ptr(u64)) {
  if z == 0 { return Option(ptr(u64)).None }
  Option(ptr(u64)).Some(p)
}
main := fn() -> u64 {
  mut x : u64 = 40
  mut m : u64 = 0
  s : Option(ptr(u64)) = Option(ptr(u64)).Some(ptr(x))
  if rd(s) != 40 { m = m + 1 }
  n : Option(ptr(u64)) = Option(ptr(u64)).None
  if rd(n) != 7 { m = m + 2 }
  mut t : Option(ptr(u64)) = n
  if rd(t) != 7 { m = m + 4 }
  t = s
  if rd(t) != 40 { m = m + 8 }
  t = Option(ptr(u64)).None
  if rd(t) != 7 { m = m + 16 }
  u := mk(1, ptr(x))
  if rd(u) != 40 { m = m + 32 }
  v := mk(0, ptr(x))
  if rd(v) != 7 { m = m + 64 }
  mut a : u64 = 0
  match u { Some(p) => { a = deref(p) } None => { a = 1 } }
  if a != 40 { m = m + 128 }
  mut b : u64 = 0
  match v { Some(p) => { b = deref(p) } None => { b = 2 } }
  if b != 2 { m = m + 256 }
  if m != 0 { return 100 + m }
  return 42
}
## expect(x86_64): run 42
## expect(aarch64): run 42
## expect(riscv64): run 42
