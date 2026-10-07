## IR slice 3a (`docs/ir-slice-3.md` §1): struct locals built through the shared IR on the register
## twins — a literal into a fresh frame object, field reads and writes at the field's width and
## signedness (narrow and `bool` fields, a BYTE-tier layout), whole-struct assignment as a `copy` that
## leaves the source independent, and a reassignment from another local. Answers 42 everywhere.
P := struct { a : i64, b : i64 }
N := struct { x : u8, y : i16, f : bool, w : u32 }
pair := fn(a : i64, b : i64) -> i64 {
  mut p := P(a = a, b = b)
  q := P(a = 7, b = 0 - 3)
  r := p
  p = q
  p.b = p.b * 2
  (p.a + p.b) * 10 + r.a + r.b + q.b + 3
}
narrow := fn() -> i64 {
  mut n := N(x = 250, y = 0 - 300, f = true, w = 70000)
  n.x = n.x + 5
  m := n
  n.y = 1
  mut r : i64 = 0
  if m.x == 255 { r = r + 1 }
  if m.y == 0 - 300 { r = r + 2 }
  if m.f { r = r + 4 }
  if m.w == 70000 { r = r + 8 }
  if n.y == 1 { r = r + 16 }
  r
}
main := fn() -> u64 {
  s := pair(1, 2)
  v := narrow()
  if s == 13 and v == 31 { return 42 }
  1
}
