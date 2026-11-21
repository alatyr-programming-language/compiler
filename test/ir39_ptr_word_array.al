## IR-39 (#1786): a struct with a fixed array of words, reached through a pointer and passed by value.
## The shared IR copies it whole and reads each element at `8 * k` past the array's `field_byte_place`,
## where x86_64's legacy constructor wrote it. Element access through the pointer itself stays refused
## (`expr Index`), so `cp` and `call_lg` are the IR-built readers. `lgm` (nine arguments, which the
## shared IR does not pass) keeps `lg_bv` and `main` on the legacy emitter, so values cross both ways.
lgm := fn(a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64, i : u64) -> u64 { a }
S := struct { a : u64, xs : [u64; 3], c : u64 }
rd := fn(p : ptr(S)) -> u64 { deref(p).xs[1] + deref(p).c }
rdp := fn(p : ptr(S)) -> u64 { p.xs[2] + p.a }
cp := fn(p : ptr(S)) -> u64 {
  v : S = deref(p)
  v.xs[0] + v.xs[2] + v.c
}
put := fn(p : ptr(mut S), q : u64) { p.xs[1] = q }
wr := fn(p : ptr(mut S), q : u64) { deref(p) = S(a = 5, xs = [q, 8, 9], c = 6) }
bv := fn(s : S) -> u64 { s.xs[2] + s.a }
lg_bv := fn(s : S) -> u64 {
  if lgm(0, 0, 0, 0, 0, 0, 0, 0, 0) != 0 { return 99 }
  s.xs[1] + s.c + 100
}
call_lg := fn(p : ptr(S)) -> u64 { lg_bv(deref(p)) }
main := fn() -> u64 {
  if lgm(0, 0, 0, 0, 0, 0, 0, 0, 0) != 0 { return 99 }
  mut s := S(a = 1, xs = [10, 20, 30], c = 2)
  if rd(ptr(s)) != 22 { return 1 }
  if rdp(ptr(s)) != 31 { return 2 }
  if cp(ptr(s)) != 42 { return 3 }
  if bv(s) != 31 { return 4 }
  if call_lg(ptr(s)) != 122 { return 5 }
  put(ptr(mut s), 7)
  if s.xs[1] != 7 or s.xs[0] != 10 or s.c != 2 { return 8 }
  wr(ptr(mut s), 3)
  if s.a != 5 or s.c != 6 or s.xs[0] != 3 or s.xs[2] != 9 { return 10 }
  42
}
## expect: run 42
