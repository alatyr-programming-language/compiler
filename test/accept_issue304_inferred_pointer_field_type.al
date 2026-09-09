## Issue #304 control — inferred pointer provenance preserves correct deep stores.
Inner := struct { f : u64, flag : bool }
Outer := struct { inner : Inner }

main := fn() -> u64 {
  mut o := Outer(inner = Inner(f = 1, flag = false))
  p := ptr(mut o)
  deref(p).inner.f = 40
  deref(p).inner.flag = true
  o.inner.f + if o.inner.flag { 2 } else { 0 }
}
