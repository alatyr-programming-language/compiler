## IR #1705: a local declared without an initializer, `mut x : T`, of an aggregate type: its frame
## object, and no store until the definite assignment (Declarations §4, §5; Types §9.4, field-sensitive,
## per element at a constant index). A struct assigned field by field, a struct assigned whole, an array
## of structs assigned element by element (whole and by field) and an array of scalars, each read after.
P := struct { a : u32, b : u64 }
main := fn() -> u64 {
  mut p : P
  p.a = 3
  p.b = 4
  mut q : P
  q = P(a = 5, b = 6)
  mut xs : [P; 2]
  xs[0] = p
  xs[1].a = 7
  xs[1].b = 8
  mut ws : [u64; 3]
  ws[0] = 9
  ws[1] = 2
  ws[2] = 1
  mut r : u64 = u64(p.a) + p.b + u64(q.a) + q.b   ## 18
  r = r + u64(xs[1].a) + xs[0].b                  ## 18 + 7 + 4 = 29
  e := xs[1]
  r + e.b - 7 + ws[0] + ws[1] + ws[2]             ## 29 + 8 - 7 + 9 + 2 + 1 = 42
}
## expect: run 42
