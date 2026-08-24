## Raw union (spec Types §6.3) — a MULTI-WORD (struct) member lives at offset 0, and the union sizes to
## it (max-member width). Write the struct member `p`, read it back and sum its fields → the value.
Pair := struct { x : u64, y : u64 }
U := union { n(u64), p(Pair) }
main := fn() -> u64 {
  u := U.p(Pair(x = 40, y = 2))
  return u.p.x + u.p.y
}
