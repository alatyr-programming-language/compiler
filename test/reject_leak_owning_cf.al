Owned := @owning struct { v : u64 }
mk := fn() -> Owned { Owned(v = 5) }
main := fn() -> u64 {
  h := mk()
  mut r := 0
  if r > 0 { r = 1 }
  0
}
