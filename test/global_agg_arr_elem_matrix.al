## e2e (ROADMAP §8.3 — AGGREGATE ARRAY ELEMENT, the array GLOBAL). The `.data` twin of
## `agg_arr_elem_matrix`: the same access shapes on a module-level array of scalar-only structs,
## addressed off the global's LABEL instead of a frame slot — field reads at word 1 and 2, a runtime
## index, a whole-element copy OUT of `.data` into a struct local, a whole-element write from a
## LITERAL, and an element FIELD write. 8 + 16 + 22 + 6 = 52.
## (A whole-element write from a struct VAR — `GS[i] = q` — is covered separately by
## `global_struct_array_elem_write_var`: when this fixture was written that shape was a silent no-op on
## x86_64, which is exactly how the bug was found; it was fixed in `8a61488` and x86 and rv64 now agree.)
Pt := struct { x : u64, y : u64, z : u64 }

mut GS := [Pt(x = 1, y = 2, z = 3), Pt(x = 4, y = 5, z = 6), Pt(x = 7, y = 8, z = 9)]

main := fn() -> u64 {
  mut r : u64 = 0
  mut i : u64 = 1
  ## constant index at word 2 + runtime index at word 1
  r = r + GS[0].z + GS[i].y              ## 3 + 5 = 8
  ## whole-element copy out of .data into a struct local
  e := GS[2]
  r = r + e.x + e.z                      ## +7 +9 = 24
  ## element write from a struct LITERAL, runtime index
  GS[i] = Pt(x = 20, y = 21, z = 22)
  r = r + GS[1].z                        ## +22 = 46
  ## element FIELD write at word 0
  GS[2].x = 6
  r = r + GS[2].x                        ## +6 = 52
  ## the copy predates the writes
  if e.y != 8 { return 1 }
  ## the field write touched ONLY word 0 of element 2
  if GS[2].z != 9 { return 2 }
  ## the literal write landed on word 0 too
  if GS[1].x != 20 { return 3 }
  ## the untouched element is intact
  if GS[0].x != 1 { return 4 }
  r
}
