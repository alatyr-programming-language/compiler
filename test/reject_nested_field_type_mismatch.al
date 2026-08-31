## A nested scalar destination must reject a text value before it reaches code generation.
I := struct { f : u64 }
S := struct { inner : I }

main := fn() -> u64 {
  mut s := S(inner = I(f = 1))
  s.inner.f = "text"
  return s.inner.f
}
