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
##
## Rows 16-34 are #422's own shape, added when the range-slice recognizer landed above the tail:
## `xs[lo..hi][i]`, a RANGE SLICE indexed DIRECTLY, which Grammar §3.4 admits as one primary plus two
## postfix steps. Every one of them used to answer frame slot 0's word (`xs[1..3][0]` -> 0, not 42) and
## then, after #425, to be refused outright. Their codes name the WRONG ANSWER rather than only the
## failing line (#386): a zero, `lo` ignored, one element either side, and the view's LENGTH returned
## in place of its element each get a code of their own, because every one of those is a plausible
## word here. Two of them are load-bearing controls: `xs[1..3][i]` starts at `lo = 1`, so an
## implementation that ignores the offset entirely cannot pass, and `xs[3..4][0]` is a LENGTH-1 view
## whose length (1) and element (55) differ, so returning the length cannot pass by coincidence.
## The OUT-OF-VIEW index is not here — it must TRAP, which ends the program — and lives in
## `arr_slice_direct_index_oob` (`run_x86_trap`, 132).
G : [u64; 4] = [71, 42, 93, 55]
S := struct { v : u64 }
C := struct { cells : [u64; 3] }
take := fn(sl : Slice(u64)) -> u64 { sl[1] }
takea := fn(a : [u64; 4]) -> u64 { a[1..3][0] }   ## #422's shape over a BY-REF array PARAM
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
  ## #422 — a range slice used DIRECTLY as an index base. `xs[1..3]` is the view {42, 93}, so
  ## element 0 is 42. `lo` is 1, not 0: an implementation that dropped the offset would answer 71.
  d0 := xs[1..3][0]
  if d0 == 0 { return 16 }                    ## frame slot 0 / a zero word — the sink #422 reported
  if d0 == 71 { return 17 }                   ## `lo` ignored: element 0 of the BASE array
  if d0 == 93 { return 18 }                   ## one element PAST the view's start
  if d0 == 2 { return 19 }                    ## the view's LENGTH instead of its element
  if d0 != 42 { return 20 }                   ## any other wrong word
  d1 := xs[1..3][1]
  if d1 == 0 { return 21 }
  if d1 == 42 { return 22 }                   ## one element BEFORE (the view's own element 0)
  if d1 == 55 { return 23 }                   ## one element PAST the view's end
  if d1 != 93 { return 24 }
  ## a LENGTH-1 view whose length and element differ, so a fix answering the length cannot pass here
  d2 := xs[3..4][0]
  if d2 == 1 { return 25 }                    ## the view's LENGTH (1)
  if d2 == 0 { return 26 }
  if d2 != 55 { return 27 }
  ## the zero-start control: `xs[0..4][1]` passes even when the offset is ignored, so it pins the
  ## OTHER half — that adding a zero offset does not shift the element either.
  if xs[0..4][1] != 42 { return 28 }
  ## the bounds need not be literals; they are re-evaluated exactly as the bound spelling does
  dlo := 1
  dhi := 3
  if xs[dlo..dhi][0] != 42 { return 29 }
  ## the two spellings of the same access must agree — the disagreement IS #422
  dv := xs[1..3]
  if dv[0] != xs[1..3][0] { return 30 }
  if dv[1] != xs[1..3][1] { return 31 }
  ## a by-reference fixed-array PARAM base, whose element-0 address is a LOADED pointer, not a `leaq`
  if takea(xs) != 42 { return 32 }
  ## an `unchecked` scope drops the bounds check and must keep the same element (CG-7)
  if unchecked xs[1..3][1] != 93 { return 33 }
  ## the PAIR path this recognizer borrows still reports the view's own length
  if xs[1..3].len != 2 { return 34 }
  42
}
