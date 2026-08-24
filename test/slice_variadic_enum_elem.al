## Functions §7.2: a SLICE variadic with an ENUM element `rest : ...Sh` — the trailing call args
## (enum ctors, disc + payload words each) are gathered into ONE contiguous runtime `[Sh]` data block
## and passed as a {ptr, len} slice. The callee reads each element BY REFERENCE like a `Slice(Sh)`
## param (`for x in rest`, then `match x`). The `...Sh` param binds `eek == 3` (enum) with the element
## stride (1 + max payload) + type span. esum(Sh.Sq(20), Sh.Tri(11)) = 20 + (11+11) = 42.
Sh := enum { Sq(u64), Tri(u64) }
esum := fn(xs : ...Sh) -> u64 {
  mut s : u64 = 0
  for x in xs {
    match x {
      Sh::Sq(n) => { s = s + n }
      Sh::Tri(n) => { s = s + n + n }
    }
  }
  return s
}
main := fn() -> u64 {
  return esum(Sh.Sq(20), Sh.Tri(11))
}
