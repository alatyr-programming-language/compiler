## §8 @packed field WRITE through an `in out` PARAMETER (spec Types §8) — the store dual of
## `packed_param_read`. An aggregate param is by REFERENCE, so `p.b = 300` in the callee stored a whole
## WORD at byte `8 * field_index` of the caller's BYTE-precise block: it missed the field entirely AND
## smeared 8 bytes over its neighbours, so the caller saw a corrupted struct — a SILENT WRONG VALUE with
## no diagnostic. The store now writes exactly the field's bytes at its packed byte offset.
## `hi`/`lo` are u64 sentinels either side of the packed struct's bytes: an over-wide store would flatten
## `c`/`d` (and, at the top of the block, the neighbouring local), so their survival proves the store is
## byte-sized, not word-sized. Returns 42.
Pk := @packed struct { a : u8, b : u16, c : u32, d : u64 }

setb := fn(in out p : Pk) {
  p.b = 300
}
seta := fn(in out p : Pk) {
  p.a = 250
}

main := fn() -> u64 {
  mut p := Pk(a = 10, b = 20, c = 100000, d = 7)
  sentinel := 987654321
  setb(p)
  seta(p)
  ## the written fields carry their new values, read back through the packed byte layout
  if u64(p.a) != 250 { return 1 }
  if u64(p.b) != 300 { return 2 }
  ## the NEIGHBOURING packed fields are untouched (a word-sized store would have flattened them)
  if u64(p.c) != 100000 { return 3 }
  if p.d != 7 { return 4 }
  ## the neighbouring LOCAL is untouched
  if sentinel != 987654321 { return 5 }
  42
}
