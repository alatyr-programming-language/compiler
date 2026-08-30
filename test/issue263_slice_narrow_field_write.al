## e2e — bounded #263a: a mutable Slice(P) field write must use the field's byte offset and width.
## The parent writes the requested `a` value but used a word-wide store, destroying `b` in the same
## eightbyte. The fixture also checks both neighbouring elements, a u16/u16 instance, a word-tier
## wide-field Slice control, and the established local-array path. The struct-field-array path is
## deliberately absent: it is the residual slice recorded on issue #263.
P8 := struct { a : u8, b : u8 }
P16 := struct { a : u16, b : u16 }
Wide := struct { a : u64, b : u64 }

main := fn() -> u64 {
  mut p8 : [P8; 3] = [P8(a = 1, b = 2), P8(a = 3, b = 4), P8(a = 5, b = 6)]
  s8 := p8[0..3]
  s8[1].a = 9
  if s8[1].a != 9 { return 1 }
  if s8[1].b != 4 { return 2 }
  if s8[0].a != 1 { return 3 }
  if s8[0].b != 2 { return 4 }
  if s8[2].a != 5 { return 5 }
  if s8[2].b != 6 { return 6 }

  mut p16 : [P16; 3] = [P16(a = 100, b = 200), P16(a = 300, b = 400), P16(a = 500, b = 600)]
  s16 := p16[0..3]
  s16[1].a = 90
  if s16[1].a != 90 { return 7 }
  if s16[1].b != 400 { return 8 }
  if s16[0].a != 100 { return 9 }
  if s16[0].b != 200 { return 10 }
  if s16[2].a != 500 { return 11 }
  if s16[2].b != 600 { return 12 }

  mut wide : [Wide; 2] = [Wide(a = 11, b = 22), Wide(a = 33, b = 44)]
  sw := wide[0..2]
  sw[1].a = 55
  if sw[1].a != 55 { return 13 }
  if sw[1].b != 44 { return 14 }
  if sw[0].a != 11 { return 15 }
  if sw[0].b != 22 { return 16 }

  mut local : [P8; 2] = [P8(a = 70, b = 71), P8(a = 80, b = 81)]
  local[1].a = 82
  if local[1].a != 82 { return 17 }
  if local[1].b != 81 { return 18 }
  if local[0].a != 70 { return 19 }
  if local[0].b != 71 { return 20 }

  42
}
