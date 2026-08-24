## e2e — alloc::omap with a MULTI-WORD STRUCT value type (Rec{a,b}). Insert OUT of key order to force
## element SHIFTs and a grow (cap 2 → inserting 6 forces two doublings). This exercises the
## generic-aggregate `deref(ptr(V))` STORE path: `omap_insert`'s value store `deref(vslot) = value` and
## its tail shift `deref(vd) = deref(vs)`, and `omap_grow`'s element copy `deref(vd) = deref(vs)` — all
## with `V` = a 2-word struct. Before the fix each moved ONE word (word 1 dropped → `.b` read 0 and the
## shifts scrambled the array). Read back through the `omap_values` slice (the Slice(V)-of-struct read
## path) and check EVERY field.
##
## ALSO exercises `omap_get` (returns `Option(V)`) for a struct `V`: delivering a multi-word STRUCT as
## a generic enum payload (`Option(V).Some(v)`) through the return-register + match-binding staging —
## formerly an open frontier that truncated word 1 / crashed the compiler (a by-ref struct-param payload
## underflowed a checked slot offset). Now `match omap_get(...) { Some(x) => x.a … }` reads every field.
om := alloc::omap
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

Rec := struct { a : u64, b : u64 }
lt := fn(a : u64, b : u64) -> bool { a < b }

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut m := om::omap(u64, Rec, ptr(ar), 2)          ## cap 2 → inserting 6 forces two doublings

  ## value = Rec(a = key*10, b = key/10); inserted OUT of key order to force tail shifts.
  om::omap_insert(u64, Rec, m, 50, Rec(a = 500, b = 5), lt).expect("i")
  om::omap_insert(u64, Rec, m, 30, Rec(a = 300, b = 3), lt).expect("i")
  om::omap_insert(u64, Rec, m, 70, Rec(a = 700, b = 7), lt).expect("i")   ## grow (len 2 -> cap 4)
  om::omap_insert(u64, Rec, m, 10, Rec(a = 100, b = 1), lt).expect("i")
  om::omap_insert(u64, Rec, m, 90, Rec(a = 900, b = 9), lt).expect("i")   ## grow (len 4 -> cap 8)
  om::omap_insert(u64, Rec, m, 20, Rec(a = 200, b = 2), lt).expect("i")

  if om::omap_len(u64, Rec, ptr(m)) != 6 { return 1 }

  ## overwrite key 30's value in place (the `deref(vslot) = value` overwrite branch).
  added := om::omap_insert(u64, Rec, m, 30, Rec(a = 333, b = 8), lt).expect("i")
  if added { return 2 }
  if om::omap_len(u64, Rec, ptr(m)) != 6 { return 3 }

  ## sorted keys ascending: 10,20,30,50,70,90 → parallel values; EVERY field must survive the shifts.
  ks := om::omap_keys(u64, Rec, ptr(m))
  vs := om::omap_values(u64, Rec, ptr(m))
  if ks[0] != 10 { return 10 }
  e0 := vs[0]
  if e0.a != 100 { return 11 }
  if e0.b != 1 { return 12 }
  if ks[1] != 20 { return 13 }
  e1 := vs[1]
  if e1.a != 200 { return 14 }
  if e1.b != 2 { return 15 }
  if ks[2] != 30 { return 16 }
  e2 := vs[2]
  if e2.a != 333 { return 17 }   ## overwritten value
  if e2.b != 8 { return 18 }
  if ks[3] != 50 { return 19 }
  e3 := vs[3]
  if e3.a != 500 { return 20 }
  if e3.b != 5 { return 21 }
  if ks[4] != 70 { return 22 }
  e4 := vs[4]
  if e4.a != 700 { return 23 }
  if e4.b != 7 { return 24 }
  if ks[5] != 90 { return 25 }
  e5 := vs[5]
  if e5.a != 900 { return 26 }
  if e5.b != 9 { return 27 }

  ## omap_get → Option(Rec): a PRESENT key delivers the whole 2-word struct payload; read BOTH fields.
  g30 := om::omap_get(u64, Rec, ptr(m), 30, lt)
  g30a := match g30 { Option.Some(x) => { x.a }  Option.None => { u64(0) } }
  if g30a != 333 { return 30 }                         ## overwritten value, word 0
  g30b := match g30 { Option.Some(x) => { x.b }  Option.None => { u64(0) } }
  if g30b != 8 { return 31 }                           ## word 1 (formerly dropped)
  g70 := om::omap_get(u64, Rec, ptr(m), 70, lt)
  match g70 { Option.Some(x) => { if x.a != 700 { return 32 }  if x.b != 7 { return 33 } }  Option.None => { return 34 } }
  ## an ABSENT key → None (discriminant path still correct).
  gx := om::omap_get(u64, Rec, ptr(m), 999, lt)
  match gx { Option.Some(x) => { return 35 }  Option.None => {} }

  return 42
}
