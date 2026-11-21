## IR-39 (#1786): a struct with a nested struct field whose fields are all a word wide, and a fixed array
## of words, reached through a pointer and passed by value. The shared IR places the child at its
## `field_byte_place`, a word per scalar, as x86_64's legacy emitter does. A child with a field narrower
## than a word stays refused (`expr Deref: struct pointee with a sub-word scalar in a nested aggregate
## field`; #1792 is x86_64's legacy literal dropping such a child). `lgm` (nine arguments, which the
## shared IR does not pass) keeps `lg_bv` and `main` on the legacy emitter.
lgm := fn(a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64, i : u64) -> u64 { a }
I := struct { q : u64, r : i64 }
S := struct { a : u64, i : I, xs : [u64; 3], c : u64 }
## IR
rd := fn(p : ptr(S)) -> u64 { deref(p).i.q + deref(p).c + u64(0 - deref(p).i.r) }
cp := fn(p : ptr(S)) -> u64 {
  v : S = deref(p)
  w : I = v.i
  v.i.q + v.c + w.q + v.a
}
puts := fn(p : ptr(mut S), q : u64) { deref(p).i = I(q = q, r = -6) }
bv := fn(s : S) -> u64 { s.i.q + s.a }
call_lg := fn(p : ptr(S)) -> u64 { lg_bv(deref(p)) }
## legacy
lg_bv := fn(s : S) -> u64 {
  if lgm(0, 0, 0, 0, 0, 0, 0, 0, 0) != 0 { return 99 }
  s.i.q + s.c + s.xs[1] + 100
}
main := fn() -> u64 {
  if lgm(0, 0, 0, 0, 0, 0, 0, 0, 0) != 0 { return 99 }
  mut s := S(a = 1, i = I(q = 30, r = -3), xs = [10, 20, 30], c = 2)
  if rd(ptr(s)) != 35 { return 1 }
  if cp(ptr(s)) != 63 { return 2 }
  if bv(s) != 31 { return 3 }
  if call_lg(ptr(s)) != 152 { return 4 }
  puts(ptr(mut s), 21)
  if s.i.q != 21 or s.i.r != -6 or s.c != 2 or s.a != 1 { return 5 }
  if s.xs[0] != 10 or s.xs[1] != 20 or s.xs[2] != 30 { return 6 }
  if call_lg(ptr(s)) != 143 { return 7 }
  42
}
## expect: run 42
