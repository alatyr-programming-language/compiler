## A nested field write does not initialize the enclosing aggregate field.
Rec := struct { a : u64, b : u64 }
Outer := struct { inner : Rec, tag : u64 }
main := fn() -> u64 {
  mut o : Outer
  o.inner.a = 42
  return o.inner
}
