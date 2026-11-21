## IR-39 (#1786): a struct with an aggregate field and unsigned narrow and `bool` fields crosses calls
## by value between legacy and IR code. The shared IR writes a narrow field at its own width into a word
## whose upper bytes are zero, which a legacy whole-word reader takes as the canonical word only for an
## unsigned field or a `bool`; a signed narrow field (`N.k`) keeps its struct to pointers. `lgm` (nine
## arguments, which the shared IR does not pass) keeps `lg_bv` and `main` on the legacy emitter.
lgm := fn(a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64, i : u64) -> u64 { a }
I := struct { q : u64, r : i64 }
S := struct { a : u64, k : u8, b : bool, i : I, c : u64 }
N := struct { a : u64, k : i8, i : I }
## IR
rd := fn(p : ptr(S)) -> u64 { deref(p).i.q + u64(deref(p).k) + deref(p).c }
put := fn(p : ptr(mut S), k : u8) { p.k = k; p.b = false }
bv := fn(s : S) -> u64 {
  mut r : u64 = s.i.q + u64(s.k) + s.a
  if s.b { r = r + 1000 }
  r
}
call_lg := fn(p : ptr(S)) -> u64 { lg_bv(deref(p)) }
call_lg_lit := fn(q : u64) -> u64 { lg_bv(S(a = 1, k = 200, b = true, i = I(q = q, r = -3), c = 2)) }
rdn := fn(p : ptr(N)) -> i64 { deref(p).i.r + i64(deref(p).k) }
putn := fn(p : ptr(mut N), k : i8) { p.k = k }
## legacy
lg_bv := fn(s : S) -> u64 {
  if lgm(0, 0, 0, 0, 0, 0, 0, 0, 0) != 0 { return 99 }
  mut r : u64 = s.i.q + u64(s.k) + s.c + 100
  if s.b { r = r + 1000 }
  r
}
main := fn() -> u64 {
  if lgm(0, 0, 0, 0, 0, 0, 0, 0, 0) != 0 { return 99 }
  mut s := S(a = 1, k = 250, b = true, i = I(q = 30, r = -3), c = 2)
  if rd(ptr(s)) != 282 { return 1 }
  if bv(s) != 1281 { return 2 }
  if call_lg(ptr(s)) != 1382 { return 3 }
  if call_lg_lit(10) != 1312 { return 4 }
  put(ptr(mut s), 7)
  if s.k != 7 or s.b or s.c != 2 or s.i.q != 30 { return 5 }
  if bv(s) != 38 or call_lg(ptr(s)) != 139 { return 6 }
  mut n := N(a = 1, k = -5, i = I(q = 1, r = -3))
  if rdn(ptr(n)) != -8 { return 7 }
  putn(ptr(mut n), -9)
  if n.k != -9 or rdn(ptr(n)) != -12 { return 8 }
  42
}
## expect: run 42
