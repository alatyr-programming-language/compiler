## e2e (#425) — the OVER-EAGERNESS control for the element-address tail's new refusal. The tail of
## `emit_index_addr` now refuses a base it cannot resolve to a frame slot instead of defaulting to
## entry 0. A census on the parent measured 1161 bases arriving at that tail (1144 over `test/*.al`,
## 17 over `package.al`'s own `src/` + `lib/`), every one a name-matched `Var` — so the refusal must
## move none of them. This fixture pins the arriving and the near-miss shapes together, each with its
## own failure code, so a refusal that fires one recognizer too wide is attributed immediately rather
## than showing up as a distant corpus row.
##
## Rows 1-9 reach the tail as a name-matched `Var` (the class the guard must let through); rows 10-14
## are claimed by a recognizer ABOVE the tail and must stay claimed. Neighbours are non-zero and
## pairwise distinct (71, 42, 93, 55) so a frame-slot-0 read cannot pass for a plausible element.
G : [u64; 4] = [71, 42, 93, 55]
S := struct { v : u64 }
C := struct { cells : [u64; 3] }
take := fn(sl : Slice(u64)) -> u64 { sl[1] }
main := fn() -> u64 {
  xs : [u64; 4] = [71, 42, 93, 55]
  if xs[1] != 42 { return 1 }
  arr : [str; 2] = ["abc", "XYZ"]
  if u64(arr[0][2]) != 99 { return 2 }
  if u64(arr[1][2]) != 90 { return 3 }
  if u64(unchecked xs[1]) != 42 { return 4 }
  v := xs[1..3]
  if v[0] != 42 { return 5 }
  if v[1] != 93 { return 6 }
  sa : [S; 2] = [S(v = 71), S(v = 42)]
  if sa[1].v != 42 { return 7 }
  t := ([71, 42, 93], 55)
  if t.0[1] != 42 { return 8 }
  if take(xs[0..4]) != 42 { return 9 }
  if u64("abc"[2]) != 99 { return 10 }
  s := "abcdef"
  if u64(bytes(s)[2]) != 99 { return 11 }
  st := C(cells = [71, 42, 93])
  if st.cells[1] != 42 { return 12 }
  if G[1] != 42 { return 13 }
  if u64(bytes(s[1..4])[0]) != 98 { return 14 }
  mut ws : [u64; 3] = [71, 42, 93]
  ws[2] = 55
  if ws[2] != 55 { return 15 }
  42
}
