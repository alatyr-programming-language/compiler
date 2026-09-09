## Issue #304 / Memory §1.6 / Types §4.3 — a store through a deep pointer-rooted field path
## must use the leaf place's declared type. The parent accepted this str-to-u64 store.
Inner := struct { f : u64, keep : u64 }
Outer := struct { inner : Inner }

main := fn() -> u64 {
  mut o := Outer(inner = Inner(f = 1, keep = 2))
  p : ptr(mut Outer) = ptr(o)
  deref(p).inner.f = "text"
  deref(p).inner.keep
}
