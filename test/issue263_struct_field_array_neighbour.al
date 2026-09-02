## CLAYOUT S4 / Types §6.1 + §6.4 — writing ONE narrow field of an array element held in a struct
## FIELD must leave every other byte of that array alone. The array field is preceded by a wide field
## so a fix that only works at element offset 0 cannot pass, and every neighbour is read back on its
## own line with a distinct non-zero value: a clobbered byte reads 0, which a summed or commutative
## assertion would hide. The wide-field rows are the control that the shared store path still works.
P8 := struct { a : u8, b : u8 }
P16 := struct { a : u16, b : u16 }
PW := struct { a : u64, b : u64 }
S8 := struct { lead : u64, items : [P8; 2] }
S16 := struct { lead : u64, items : [P16; 2] }
SW := struct { lead : u64, items : [PW; 2] }

main := fn() -> u64 {
  mut s8 := S8(lead = 55, items = [P8(a = 11, b = 22), P8(a = 33, b = 44)])
  s8.items[1].a = 99
  if s8.lead != 55 { return 100 }
  if u64(s8.items[1].a) != 99 { return 101 }
  if u64(s8.items[1].b) != 44 { return 102 }
  if u64(s8.items[0].a) != 11 { return 103 }
  if u64(s8.items[0].b) != 22 { return 104 }
  s8.items[0].b = 77
  if u64(s8.items[0].a) != 11 { return 105 }
  if u64(s8.items[0].b) != 77 { return 106 }
  if u64(s8.items[1].a) != 99 { return 107 }
  if u64(s8.items[1].b) != 44 { return 108 }
  if s8.lead != 55 { return 109 }

  mut s16 := S16(lead = 66, items = [P16(a = 111, b = 222), P16(a = 333, b = 444)])
  s16.items[1].a = 999
  if s16.lead != 66 { return 110 }
  if u64(s16.items[1].a) != 999 { return 111 }
  if u64(s16.items[1].b) != 444 { return 112 }
  if u64(s16.items[0].a) != 111 { return 113 }
  if u64(s16.items[0].b) != 222 { return 114 }
  s16.items[0].a = 888
  if u64(s16.items[0].a) != 888 { return 115 }
  if u64(s16.items[0].b) != 222 { return 116 }
  if u64(s16.items[1].a) != 999 { return 117 }
  if u64(s16.items[1].b) != 444 { return 118 }

  mut sw := SW(lead = 77, items = [PW(a = 1001, b = 2002), PW(a = 3003, b = 4004)])
  sw.items[1].a = 5005
  if sw.lead != 77 { return 119 }
  if sw.items[1].a != 5005 { return 120 }
  if sw.items[1].b != 4004 { return 121 }
  if sw.items[0].a != 1001 { return 122 }
  if sw.items[0].b != 2002 { return 123 }
  42
}
