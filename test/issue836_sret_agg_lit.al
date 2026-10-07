## e2e / issue #836 — a WIDE (hidden result pointer) struct or enum returned as a literal keeps every
## component.
##
## The wide-return writer pushed one scalar per field or payload: an enum- or struct-literal field, a
## `str` field and a bare `Option.Some(p)` stored the `$0` placeholder (or word 0 alone) and displaced
## every later field. The literal is now built by the frame writer and copied through the result
## pointer whole.
##
## 42 means every return held. Each miss owns its own code from 100 up.
N := struct { v : u64 }
S := struct { x : u64, y : u64 }
P := enum { PN, PV(u64, u64) }
W := struct { a : u64, p : P, c : u64, d : u64, e : u64, f : u64 }
V := struct { a : u64, s : S, c : u64, d : u64, e : u64, f : u64, g : u64 }
T := struct { a : u64, s : str, c : u64, d : u64, e : u64, f : u64, g : u64 }
O := struct { a : u64, o : Option(ptr(N)), c : u64, d : u64, e : u64, f : u64, g : u64, h : u64 }
S7 := struct { a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64 }
F := enum { A(u64, Option(ptr(N))), B(S7) }
mkw := fn() -> W { W(a = 1, p = P.PV(30, 12), c = 3, d = 4, e = 5, f = 6) }
mkv := fn() -> V { V(a = 1, s = S(x = 40, y = 2), c = 3, d = 4, e = 5, f = 6, g = 7) }
mkt := fn() -> T { T(a = 1, s = "abcdefgh", c = 3, d = 4, e = 5, f = 6, g = 7) }
mko := fn(p : ptr(N)) -> O { O(a = 1, o = Option.Some(p), c = 3, d = 4, e = 5, f = 6, g = 7, h = 8) }
mkf := fn(p : ptr(N)) -> F { F.A(8, Option.Some(p)) }
main := fn() -> u64 {
  w := mkw()
  match w.p { P::PN => { return 100 }; P::PV(x, y) => { if x + y != 42 or w.f != 6 or w.c != 3 { return 101 } } }
  v := mkv()
  if v.g != 7 { return 102 }
  if v.s.x + v.s.y != 42 { return 103 }
  t := mkt()
  if t.g != 7 or t.s.len != 8 { return 104 }
  n := N(v = 34)
  o := mko(ptr(n))
  match o.o { Some(q) => { if deref(q).v + o.h != 42 { return 105 } }; None => { return 106 } }
  f := mkf(ptr(n))
  match f { F::A(k, fo) => { match fo { Some(q) => { if deref(q).v + k != 42 { return 107 } }; None => { return 108 } } }; F::B(s) => { return 109 } }
  42
}
