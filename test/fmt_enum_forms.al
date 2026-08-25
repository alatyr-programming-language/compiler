## §5 fmt — two recent ENUM forms fmt had never been shown: a module-level ARRAY GLOBAL of enum values
## (a mutable global array initialized with payloaded variant literals) and a WIDE-enum
## `return W.Some(<7-word struct>)` (the SRET return path). Both round-trip today; this locks them.
##   GE[0] 1 + GE[1] 20 + Big sum 28 = 49
E := enum {
  A(u64),
  B(u64),
}

Big := struct {
  a : u64,
  b : u64,
  c : u64,
  d : u64,
  e : u64,
  f : u64,
  g : u64,
}

W := enum {
  Some(Big),
  None,
}

mut GE := [E.A(1), E.B(2)]

mkV := fn() -> W {
  return W.Some(Big(a = 1, b = 2, c = 3, d = 4, e = 5, f = 6, g = 7))
}

main := fn() -> u64 {
  x := GE[0]
  y := GE[1]
  s := match x { E::A(n) => n, E::B(n) => n * 10 }
  t := match y { E::A(n) => n, E::B(n) => n * 10 }
  v := mkV()
  w := match v { W::Some(p) => p.a + p.b + p.c + p.d + p.e + p.f + p.g, W::None => 0 }
  return s + t + w
}
