## IR-39 (#1786): a struct with a niche-folded `Option(ptr(u64))` field — one pointer word, `None` the
## null word (Types §6.2, Memory §4.2) — reached through a pointer and passed by value. `lgm` (nine
## arguments, which the shared IR does not pass) keeps `lg_bv` and `main` on the legacy emitter, so the
## folded word crosses between legacy and IR code in both directions.
lgm := fn(a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64, i : u64) -> u64 { a }
S := struct { a : u64, o : Option(ptr(u64)), c : u64 }
## IR
rdp := fn(p : ptr(S)) -> u64 {
  match p.o { Option::Some(q) => { return deref(q) + p.a }; Option::None => { return 3 } }
}
cp := fn(p : ptr(S)) -> u64 {
  v : S = deref(p)
  match v.o { Option::Some(q) => { return deref(q) + v.c }; Option::None => { return 3 } }
}
put := fn(p : ptr(mut S), q : ptr(u64)) { p.o = Option(ptr(u64)).Some(q) }
clr := fn(p : ptr(mut S)) { p.o = Option(ptr(u64)).None }
bv := fn(s : S) -> u64 {
  match s.o { Option::Some(q) => { return deref(q) + s.a }; Option::None => { return 3 } }
}
call_lg := fn(p : ptr(S)) -> u64 { lg_bv(deref(p)) }
## legacy
lg_bv := fn(s : S) -> u64 {
  if lgm(0, 0, 0, 0, 0, 0, 0, 0, 0) != 0 { return 99 }
  match s.o { Option::Some(q) => { return deref(q) + s.c + 100 }; Option::None => { return 4 } }
}
main := fn() -> u64 {
  if lgm(0, 0, 0, 0, 0, 0, 0, 0, 0) != 0 { return 99 }
  mut x : u64 = 30
  mut y : u64 = 20
  mut s := S(a = 1, o = Option(ptr(u64)).Some(ptr(x)), c = 2)
  if rdp(ptr(s)) != 31 { return 1 }
  if cp(ptr(s)) != 32 { return 2 }
  if bv(s) != 31 { return 3 }
  if call_lg(ptr(s)) != 132 { return 4 }
  clr(ptr(mut s))
  match s.o { Option::Some(q) => { return 5 }; Option::None => {} }
  if cp(ptr(s)) != 3 or call_lg(ptr(s)) != 4 { return 6 }
  put(ptr(mut s), ptr(y))
  match s.o { Option::Some(q) => { if deref(q) != 20 { return 7 } }; Option::None => { return 8 } }
  if s.a != 1 or s.c != 2 { return 9 }
  if call_lg(ptr(s)) != 122 { return 10 }
  42
}
## expect: run 42
