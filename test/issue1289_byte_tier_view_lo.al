## #1289 — a range view `u[1..3]` over an array of a byte-tier struct (Types §6.1: `u8` fields, so the
## element is 2 bytes, §6.4 stride 2) starts at element 1: `qs[i]` reads and writes `u[1 + i]` (Types
## `Slice(T)` indexing; I11). NON-VACUOUS: on the parent da8f96af (native x86_64, tree Stage1) this
## answers 1 (`qs[0].a` read 0, the view's base scaled by a word per element).
Q := struct { a : u8, b : u8 }
main := fn() -> u64 {
  mut u : [Q; 3] = [Q(a = 1, b = 2), Q(a = 3, b = 4), Q(a = 5, b = 6)]
  qs := u[1..3]
  if u64(qs[0].a) != 3 { return 1 }
  if u64(qs[1].b) != 6 { return 2 }
  qs[1].b = 9
  if u64(u[2].b) != 9 { return 3 }
  42
}
## expect: run 42
