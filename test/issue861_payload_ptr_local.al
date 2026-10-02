## e2e / issue #861 — a local initialized from an enum payload's `ptr(S)` binding is typed.
##
## `collect_slots` sized `m := deref(q)` / `r := q` from the initializer before the payload binding `q`
## had a type, so `m` took one untyped word (its fields read 0) and `r` was an untyped scalar
## (`deref(r).v` read 0). Now an arm with a `deref` copy types `q` for its body, and a plain copy is
## retyped in place as the pointer it is.
##
## 42 means every read held. Each miss owns its own code from 100 up.
N := struct { v : u64, w : u64 }
E := enum { B(ptr(N)), C(u64, ptr(N)), Z }
get_w := fn(p : ptr(N)) -> u64 { deref(p).w }
main := fn() -> u64 {
  n := N(v = 7, w = 9)
  e := E.B(ptr(n))
  match e { B(q) => { m := deref(q); if m.w != 9 { return 100 } }; C(k, q) => { return 101 }; Z => { return 101 } }
  match e { B(q) => { r := q; if get_w(q) + deref(r).v != 16 { return 102 } }; C(k, q) => { return 103 }; Z => { return 103 } }
  f := E.C(5, ptr(n))
  match f { B(q) => { return 104 }; C(k, q) => { m2 := deref(q); r2 := q; return m2.w + deref(r2).v + k + 21 }; Z => { return 105 } }
  106
}
