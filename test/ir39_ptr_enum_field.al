## IR-39 (#1786): a struct with enum fields — a payload enum, a payload-less one and an `Option(u64)` —
## reached through a pointer and passed by value. The shared IR lays each one out as x86_64's legacy
## emitter does: the tag word, then one word per payload component (`lower_layout::field_byte_place`,
## `field_words`). The functions that call `lgm` (nine arguments, which the shared IR does not pass) stay
## on the legacy emitter, so values cross between legacy and IR code in both directions: legacy `main`
## builds the struct and the IR reads it, the IR writes it and legacy reads it back, the IR passes it by
## value to a legacy callee, and legacy passes it to an IR callee.
lgm := fn(a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64, i : u64) -> u64 { a }
E := enum { A, B(u64), C(i64, u64) }
K := enum { X, Y, Z }
S := struct { a : u64, e : E, k : K, o : Option(u64), c : u64 }
ev := fn(e : E) -> u64 {
  mut r : u64 = 0
  match e { E.A => { r = 1 }; E.B(x) => { r = x }; E.C(y, z) => { r = z + 50 } }
  r
}
kv := fn(k : K) -> u64 {
  mut r : u64 = 0
  match k { K.X => { r = 1000 }; K.Y => { r = 2000 }; K.Z => { r = 3000 } }
  r
}
ov := fn(o : Option(u64)) -> u64 { match o { Option::Some(q) => { return q }; Option::None => { return 7 } } }
## IR: field reads through the pointer, a whole copy, writes, and a by-value parameter
rd := fn(p : ptr(S)) -> u64 { ev(deref(p).e) + kv(deref(p).k) + ov(deref(p).o) + deref(p).c }
cp := fn(p : ptr(S)) -> u64 {
  v : S = deref(p)
  ev(v.e) + kv(v.k) + ov(v.o) + v.c
}
put := fn(p : ptr(mut S), q : u64) {
  deref(p).e = E.C(-1, q)
  deref(p).k = K.Z
  deref(p).o = Option(u64).None
}
bv := fn(s : S) -> u64 { ev(s.e) + kv(s.k) + ov(s.o) + s.a }
call_lg := fn(p : ptr(S)) -> u64 { lg_bv(deref(p)) }
## legacy
lg_bv := fn(s : S) -> u64 {
  if lgm(0, 0, 0, 0, 0, 0, 0, 0, 0) != 0 { return 99 }
  mut r : u64 = 0
  match s.e { E.A => { r = 1 }; E.B(x) => { r = x }; E.C(y, z) => { r = z + 50 } }
  match s.k { K.X => { r = r + 1000 }; K.Y => { r = r + 2000 }; K.Z => { r = r + 3000 } }
  r + ov(s.o) + s.c + 100
}
main := fn() -> u64 {
  if lgm(0, 0, 0, 0, 0, 0, 0, 0, 0) != 0 { return 99 }
  mut s := S(a = 1, e = E.B(30), k = K.Y, o = Option(u64).Some(4), c = 2)
  if rd(ptr(s)) != 2036 { return 1 }
  if cp(ptr(s)) != 2036 { return 2 }
  if bv(s) != 2035 { return 3 }
  if call_lg(ptr(s)) != 2136 { return 4 }
  put(ptr(mut s), 9)
  match s.e { E.C(y, z) => { if y != -1 or z != 9 { return 5 } }; E.A => { return 6 }; E.B(x) => { return 7 } }
  match s.k { K.Z => {}; K.X => { return 8 }; K.Y => { return 9 } }
  if ov(s.o) != 7 { return 10 }
  if s.a != 1 or s.c != 2 { return 11 }
  if rd(ptr(s)) != 3068 { return 12 }
  if call_lg(ptr(s)) != 3168 { return 13 }
  42
}
## expect: run 42
