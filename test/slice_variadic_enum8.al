## Functions §7.2: a SLICE variadic with an ENUM element `xs : ...Sh` gathering >6 (here EIGHT) trailing
## enum args into one contiguous runtime `[Sh]` data block — exercises the lifted `ng > 6` cap on the
## AGGREGATE gather path with an enum element (disc + payload per slot). esum(Sq(5)x6, Sq(6)x2) = 42.
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
  return esum(Sh.Sq(5), Sh.Sq(5), Sh.Sq(5), Sh.Sq(5), Sh.Sq(5), Sh.Sq(5), Sh.Sq(6), Sh.Sq(6))
}
