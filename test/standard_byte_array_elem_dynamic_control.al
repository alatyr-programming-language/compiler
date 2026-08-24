## Focused control for CLAYOUT S3(d): preserve the historical word-tier aggregate path and the
## independent plain-byte-array path while the byte-tier aggregate path is narrowed.
Word := struct { x : u64, y : u64 }
main := fn() -> u64 {
  mut ws : [Word; 4]
  ws[0] = Word(x = 20, y = 22)
  ws[1] = Word(x = 24, y = 26)
  ws[2] = Word(x = 28, y = 30)
  ws[3] = Word(x = 32, y = 34)
  mut i := 1
  ws[i] = Word(x = 30, y = 33)
  if ws[0].y != 22 { return 1 }
  if ws[i].x != 30 { return 2 }
  ws[i].y = 35
  if ws[1].y != 35 { return 3 }
  if ws[0].y != 22 { return 4 }

  42
}
