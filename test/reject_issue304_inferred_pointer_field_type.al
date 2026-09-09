## Issue #304 / Memory §1.6 / Declarations §3.2 — an inferred pointer retains the
## addressed local's place type. The parent accepted this str-to-u64 leaf store.
Inner := struct { f : u64, keep : u64 }
Outer := struct { inner : Inner }

main := fn() -> u64 {
  mut o := Outer(inner = Inner(f = 1, keep = 2))
  p := ptr(mut o)
  deref(p).inner.f = "text"
  deref(p).inner.keep
}
