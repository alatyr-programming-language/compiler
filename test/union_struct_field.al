## §6.3/OP-4 union-as-struct-field: the union occupies its max member width with no tag word.
Pair := struct { x : u64, y : u64 }
U := union { n(u64), p(Pair) }
Holder := struct { u : U, marker : u64 }
PackedHolder := @packed struct { u : U, marker : u64 }

main := fn() -> u64 {
  h := Holder(u = U.p(Pair(x = 1, y = 2)), marker = 3)
  p := PackedHolder(u = U.p(Pair(x = 1, y = 2)), marker = 3)
  return h.u.p.x + h.u.p.y + h.marker + p.u.p.x + p.u.p.y + p.marker
}
