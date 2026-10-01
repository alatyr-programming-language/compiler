## #858 — a field read through an ordinary enum payload's `ptr(S)` binding read 0 on x86_64.
##
## `E := enum { B(ptr(N)), Z }`, `match e { B(q) => deref(q).w }` compiled clean and returned 0: the
## parser keeps only the HEAD token of a payload type (`ptr`), so the binding was typed from a bare
## `ptr` with no pointee and the field read had nothing to resolve. #768 had fixed the same read for
## `Option(ptr(S))` only, where the generic substitution happens to hand back the whole `ptr(S)`. The
## binding's pointee is now read from the variant's declared component type in source, for every
## binding of every arm, in the statement, value and tail matches. A local INITIALIZED from the binding
## (`m := deref(q)`, `r := q`) is still sized untyped at collect time; that is #861, not covered here.
##
## Each check returns its own code from 100 on a miss; all holding exits 42.
N := struct { v : u64, w : u64 }
I := struct { a : u64, b : u64 }
H := struct { v : u64, i : I }
K := enum { A(u64), Bz }

E := enum { B(ptr(N)), Z }
M := enum { B(ptr(mut N)), Z }
D := enum { P(u64, ptr(N)), Z }
DM := enum { P(u64, ptr(mut N)), Z }
EH := enum { B(ptr(H)), Z }
W := enum { P(ptr(K)), Z }
G := fn(T : type) -> type { return enum { B(ptr(T)), Z } }

## statement match, `return` from the arm
stmt_read := fn(e : E) -> u64 {
  match e { B(q) => { return deref(q).w }; Z => { return 0 } }
  0
}
## the first field (offset 0) and arithmetic on the read
stmt_first_plus := fn(e : E) -> u64 {
  match e { B(q) => { return deref(q).v + 1 }; Z => { return 0 } }
  0
}
## value match bound to an annotated local
value_read := fn(e : E) -> u64 {
  r : u64 = match e { B(q) => deref(q).w, Z => 0 }
  r
}
## tail match
tail_read := fn(e : E) -> u64 {
  match e { B(q) => deref(q).w, Z => 0 }
}
## the field read without spelling the `deref`
auto_read := fn(e : E) -> u64 {
  match e { B(q) => { return q.w }; Z => { return 0 } }
  0
}
## the second component of a multi-payload variant
multi_read := fn(e : D) -> u64 {
  match e { P(k, q) => { return deref(q).w + k }; Z => { return 0 } }
  0
}
## a nested aggregate field
nested_read := fn(e : EH) -> u64 {
  r : u64 = match e { B(q) => deref(q).i.b, Z => 0 }
  r
}
## the enum reached through a pointer parameter
by_ptr_read := fn(e : ptr(E)) -> u64 {
  match deref(e) { B(q) => deref(q).w, Z => 0 }
}
## a write through a `ptr(mut N)` payload
write_through := fn(e : M) {
  match e { B(q) => { deref(q).w = 11 }; Z => {} }
}
write_multi := fn(e : DM) {
  match e { P(k, q) => { deref(q).v = k + 30 }; Z => {} }
}
## a pointer-to-enum payload matched through `deref`
enum_pointee := fn(w : W) -> u64 {
  r : u64 = match w { P(q) => match deref(q) { A(x) => x * 2, Bz => 1 }, Z => 0 }
  r
}
## a generic enum's `ptr(T)` payload at `T = N`
generic_read := fn(g : G(N)) -> u64 {
  match g { B(q) => { return deref(q).w }; Z => { return 0 } }
  0
}
mk := fn(p : ptr(N)) -> E { E.B(p) }

main := fn() -> u64 {
  n := N(v = 7, w = 9)
  e := E.B(ptr(n))
  if stmt_read(e) != 9 { return 100 }
  if stmt_first_plus(e) != 8 { return 101 }
  if value_read(e) != 9 { return 102 }
  if tail_read(e) != 9 { return 103 }
  if auto_read(e) != 9 { return 104 }
  if multi_read(D.P(5, ptr(n))) != 14 { return 105 }
  h := H(v = 1, i = I(a = 3, b = 13))
  if nested_read(EH.B(ptr(h))) != 13 { return 106 }
  if by_ptr_read(ptr(e)) != 9 { return 107 }
  mut m := N(v = 7, w = 9)
  write_through(M.B(ptr(m)))
  if m.w != 11 { return 108 }
  write_multi(DM.P(4, ptr(m)))
  if m.v != 34 { return 109 }
  k := K.A(21)
  if enum_pointee(W.P(ptr(k))) != 42 { return 110 }
  g : G(N) = G(N).B(ptr(n))
  if generic_read(g) != 9 { return 111 }
  if tail_read(mk(ptr(n))) != 9 { return 112 }
  if tail_read(E.Z) != 0 { return 113 }
  42
}
