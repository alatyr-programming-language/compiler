## e2e / issue #846 — `deref(p) = S(…)` with an `Option(ptr(T))` field.
##
## Storing a struct literal through a pointer pushed every field as a scalar: a `Some(p)` literal became
## the `0` placeholder (None) and a bare `Option.None` its variant index. Each field is now pushed by its
## declared type, so a folded field stores its one folded word.
##
## 42 means every store held. Each miss owns its own code from 100 up.
N := struct { v : u64, next : Option(ptr(mut N)) }
H := struct { k : u64, head : Option(ptr(mut N)), m : u64 }
main := fn() -> u64 {
  mut b := N(v = 30, next = Option.None)
  mut h := H(k = 0, head = Option.None, m = 0)
  p : ptr(mut H) = ptr(mut h)
  deref(p) = H(k = 2, head = Option.Some(ptr(mut b)), m = 10)
  match h.head { Some(q) => { if deref(q).v != 30 { return 100 } }; None => { return 101 } }
  if h.k + h.m != 12 { return 102 }
  deref(p) = H(k = 1, head = Option.None, m = 1)
  match h.head { Some(_q) => { return 103 }; None => {} }
  deref(p) = H(k = 40, head = Option(ptr(mut N)).Some(ptr(mut b)), m = 2)
  match h.head { Some(_q) => { return h.k + h.m }; None => { return 104 } }
  105
}
