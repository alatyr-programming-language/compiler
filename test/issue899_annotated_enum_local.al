## e2e / issue #899 — an annotated enum local takes its DECLARED width.
##
## `h : Option(S) = Option.None` was sized from the bare literal head `Option`, whose `T` counts one
## word, so `h` got two words of a three-word value: a whole-value store through `ptr(h)` overran the
## neighbouring local, and a re-assignment was refused. The annotation now decides the layout.
##
## 42 means every value held. Each miss owns its own code from 100 up.
S := struct { x : u64, y : u64 }
set := fn(p : ptr(mut Option(S)), v : Option(S)) { deref(p) = v }
main := fn() -> u64 {
  mut g : u64 = 5
  mut h : Option(S) = Option.None
  mut k : u64 = 7
  set(ptr(h), Option.Some(S(x = 30, y = 0)))
  if g != 5 or k != 7 { return 100 }
  mut t : Option(S) = Option.None
  t = Option.Some(S(x = 0, y = 0))
  match t { Some(s) => { if s.y != 0 { return 101 } }; None => { return 102 } }
  match h { Some(s) => { return s.x + s.y + g + k }; None => { return 103 } }
}
