## A field read is valid once that field is initialized, even while another field remains unreadied.
P := struct { a : u64, b : u64 }
main := fn() -> u64 {
  mut p : P
  p.a = 42
  return p.a
}
