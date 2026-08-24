## Reading an unreadied sibling field remains rejected after a different field is initialized.
P := struct { a : u64, b : u64 }
main := fn() -> u64 {
  mut p : P
  p.a = 40
  return p.a + p.b
}
