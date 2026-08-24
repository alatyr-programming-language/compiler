## constant-index DA for a struct field containing an array of structs.
Inner := struct { v : u64, w : u64 }
Outer := struct { xs : [Inner; 2] }
main := fn() -> u64 {
  mut p : Outer
  p.xs[0].w = 42
  return p.xs[0].w
}
