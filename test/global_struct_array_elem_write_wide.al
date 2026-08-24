## e2e — the WIDE (>7-word, past every return-register class) twin of
## `global_struct_array_elem_write_var`: a whole-element write into a mutable STRUCT-array GLOBAL
## from a struct VARIABLE whose element is 9 words. The var path is a plain frame-word→`.data` copy,
## so width is just a longer loop — this pins that no word past the ABI register classes is dropped
## and that element 0 (a full 9-word stride away) is untouched. 45 + 1 = 46.
W := struct { a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64, i : u64 }

mut GW := [W(a = 1, b = 1, c = 1, d = 1, e = 1, f = 1, g = 1, h = 1, i = 1),
           W(a = 0, b = 0, c = 0, d = 0, e = 0, f = 0, g = 0, h = 0, i = 0)]

main := fn() -> u64 {
  q := W(a = 1, b = 2, c = 3, d = 4, e = 5, f = 6, g = 7, h = 8, i = 9)
  mut k : u64 = 1
  GW[k] = q
  ## every one of the nine words landed at the right offset inside element 1
  if GW[1].a != 1 { return 1 }
  if GW[1].e != 5 { return 2 }
  if GW[1].h != 8 { return 3 }
  if GW[1].i != 9 { return 4 }
  ## element 0 sits a full 9-word stride below and must be untouched
  if GW[0].a != 1 { return 5 }
  if GW[0].i != 1 { return 6 }
  GW[1].a + GW[1].b + GW[1].c + GW[1].d + GW[1].e + GW[1].f + GW[1].g + GW[1].h + GW[1].i + GW[0].i   ## 45 + 1 = 46
}
