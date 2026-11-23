## e2e / issue #340 — a typed local's layout does not depend on how much whitespace precedes its `:`.
##
## Grammar §2.5 permits any whitespace between tokens, so `mut xs<spaces>: [Row; 2]` declares a two-element
## array of a two-word struct however wide the gap. The source-recovery scan read a fixed 512-byte window
## from the binding's name: once the `:` fell outside it, the local was reserved as a scalar word and
## element 1 was addressed at stride 8 instead of 16 (Types §6.4). The gaps are the boundary's neighbours
## (501, 502, 503 spaces) and an ordinary single space as the control. Each binding owns a code from 11 up;
## 42 means every one kept its 16-byte stride.
##
## NON-VACUOUS: at `8f1dba16` and its parent (omen, native x86_64) the 502-space binding answered 0 where
## 31 is due (the 501-space one 31). At `dc9e18e2` every gap answers 31 on all four backends.
Row := struct { a : u64, b : u64 }
main := fn() -> u64 {
  mut xs1 : [Row; 2]
  xs1[0] = Row(a = 11, b = 12)
  xs1[1] = Row(a = 21, b = 31)
  if xs1[1].b != 31 { return 11 }
  if xs1[0].a != 11 { return 21 }
  mut xs501                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     : [Row; 2]
  xs501[0] = Row(a = 11, b = 12)
  xs501[1] = Row(a = 21, b = 31)
  if xs501[1].b != 31 { return 12 }
  if xs501[0].a != 11 { return 22 }
  mut xs502                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      : [Row; 2]
  xs502[0] = Row(a = 11, b = 12)
  xs502[1] = Row(a = 21, b = 31)
  if xs502[1].b != 31 { return 13 }
  if xs502[0].a != 11 { return 23 }
  mut xs503                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       : [Row; 2]
  xs503[0] = Row(a = 11, b = 12)
  xs503[1] = Row(a = 21, b = 31)
  if xs503[1].b != 31 { return 14 }
  if xs503[0].a != 11 { return 24 }
  42
}
## expect: run 42
