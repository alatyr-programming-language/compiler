## CLAYOUT S4/S3(d): a direct array field of a plain struct must preserve the element's
## byte-layout fields when a nested field is written. The two narrow pairs share one machine
## word under the old word-wide store, so each check reads the written element's neighbour and
## the adjacent element after `s.items[1].a = value`.
P8 := struct { a : u8, b : u8 }
S8 := struct { items : [P8; 2] }
P16 := struct { a : u16, b : u16 }
S16 := struct { items : [P16; 2] }
PWide := struct { a : u64, b : u64 }
SWide := struct { items : [PWide; 2] }

main := fn() -> u64 {
  mut s8 := S8(items = [P8(a = 1, b = 2), P8(a = 3, b = 4)])
  s8.items[1].a = 9
  if u64(s8.items[1].a) != 9 { return 1 }
  if u64(s8.items[1].b) != 4 { return 2 }
  if u64(s8.items[0].a) != 1 { return 3 }
  if u64(s8.items[0].b) != 2 { return 4 }

  mut s16 := S16(items = [P16(a = 11, b = 12), P16(a = 13, b = 14)])
  s16.items[1].a = 99
  if u64(s16.items[1].a) != 99 { return 5 }
  if u64(s16.items[1].b) != 14 { return 6 }
  if u64(s16.items[0].a) != 11 { return 7 }
  if u64(s16.items[0].b) != 12 { return 8 }

  mut sw := SWide(items = [PWide(a = 21, b = 22), PWide(a = 23, b = 24)])
  sw.items[1].a = 33
  if sw.items[1].a != 33 { return 9 }
  if sw.items[1].b != 24 { return 10 }
  if sw.items[0].a != 21 { return 11 }
  if sw.items[0].b != 22 { return 12 }

  mut local : [P8; 2] = [P8(a = 31, b = 32), P8(a = 33, b = 34)]
  local[1].a = 41
  if u64(local[1].a) != 41 { return 13 }
  if u64(local[1].b) != 34 { return 14 }
  if u64(local[0].a) != 31 { return 15 }
  if u64(local[0].b) != 32 { return 16 }
  42
}
