## e2e / issue #892 — an aggregate literal stored through a pointer keeps every component.
##
## `deref(p) = E.V(…)` / `deref(p) = S(…)` pushed one scalar per payload or field. A component wider
## than one word (a struct or payloaded-enum literal, a `str`, a multi-word struct var, a struct
## call) and a bare `Option.Some(p)` (whose folded word is not its variant index) were stored as the
## `$0` placeholder or as word 0 alone, and the components after them were displaced. The literal is
## now built by the frame writer (`emit_struct_assign` / `emit_enum_assign`) and copied whole. The
## frame writers themselves kept only word 0 of a struct-returning call (an enum payload) or stored
## nothing (a struct field); both now deliver the call's every word.
##
## 42 means every store held. Each miss owns its own code from 100 up.
N := struct { v : u64, next : Option(ptr(mut N)) }
S := struct { x : u64, y : u64 }
P := enum { PN, PV(u64, u64) }
E := enum { A(u64, Option(ptr(mut N))), B(S), C(str), Z }
W := struct { a : u64, p : P, s : S, t : str, c : u64 }
mk := fn() -> S { S(x = 5, y = 6) }
main := fn() -> u64 {
  mut n := N(v = 30, next = Option.None)
  mut e : E = E.Z
  pe : ptr(mut E) = ptr(e)
  deref(pe) = E.A(1, Option.Some(ptr(mut n)))
  match e { E::A(k, o) => { match o { Some(q) => { if deref(q).v + k != 31 { return 100 } }; None => { return 101 } } }; E::B(s) => { return 102 }; E::C(t) => { return 102 }; E::Z => { return 102 } }
  deref(pe) = E.B(S(x = 7, y = 8))
  match e { E::A(k, o) => { return 103 }; E::B(s) => { if s.x + s.y != 15 { return 104 } }; E::C(t) => { return 103 }; E::Z => { return 103 } }
  deref(pe) = E.C("twelve chars")
  match e { E::A(k, o) => { return 105 }; E::B(s) => { return 105 }; E::C(t) => { if t.len != 12 { return 106 } }; E::Z => { return 105 } }
  sv := S(x = 9, y = 10)
  deref(pe) = E.B(sv)
  match e { E::A(k, o) => { return 107 }; E::B(s) => { if s.y != 10 { return 108 } }; E::C(t) => { return 107 }; E::Z => { return 107 } }
  deref(pe) = E.B(mk())
  match e { E::A(k, o) => { return 109 }; E::B(s) => { if s.y != 6 { return 110 } }; E::C(t) => { return 109 }; E::Z => { return 109 } }
  le := E.B(mk())
  match le { E::A(k, o) => { return 111 }; E::B(s) => { if s.y != 6 { return 112 } }; E::C(t) => { return 111 }; E::Z => { return 111 } }
  mut w := W(a = 0, p = P.PN, s = S(x = 0, y = 0), t = "", c = 0)
  pw : ptr(mut W) = ptr(w)
  deref(pw) = W(a = 1, p = P.PV(2, 3), s = S(x = 4, y = 5), t = "abcdef", c = 6)
  match w.p { P::PN => { return 113 }; P::PV(x, y) => { if x + y != 5 { return 114 } } }
  if w.s.x + w.s.y != 9 { return 115 }
  if w.t.len != 6 { return 116 }
  if w.c != 6 { return 117 }
  lw := W(a = 1, p = P.PN, s = mk(), t = "", c = 2)
  if lw.s.y != 6 or lw.c != 2 { return 118 }
  42
}
