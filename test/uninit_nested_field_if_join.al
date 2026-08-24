## A leaf written on every branch is initialized after the branch join.
Rec := struct { a : u64, b : u64 }
Outer := struct { inner : Rec, tag : u64 }
main := fn() -> u64 {
  mut o : Outer
  if true { o.inner.a = 20 } else { o.inner.a = 22 }
  return o.inner.a * 2
}
