## §8 @offset(N) / @align(N) / @endian(big) fields read off a BY-VALUE PARAMETER (spec Types §8) — the
## attribute-lever dual of `packed_param_read`. All three levers extend the @packed byte-precise layout,
## so all three were silently wrong off a by-ref (by-value) param, which fell to the word-sized read:
##  - `@offset`: the OVERLAP (`hi`/`lo` both at byte 0) disappeared — each read its own word.
##  - `@align`:  the cursor rounding vanished — `b` read word 1 instead of byte 4.
##  - `@endian(big)`: the byte-swap on load never happened AND the overlay fields read other words.
## Each is re-checked in the callee against exactly the value the caller's own local read yields, so a
## disagreement between the two spellings is a failure. Returns 42.
Reg := @packed struct { hi : u32, @offset(0) lo : u32, tail : u8 }
Al  := @packed struct { a : u8, @align(4) b : u32, c : u8 }
W32 := @packed struct { @endian(big) v : u32, @offset(0) raw : u32, @offset(0) b0 : u8, @offset(3) b3 : u8 }

## @offset overlap: hi and lo alias byte 0, lo written last, so hi reads lo's 42
takeoff := fn(r : Reg) -> u64 {
  if u64(r.hi) != 42 { return 1 }
  if u64(r.lo) != 42 { return 2 }
  if u64(r.tail) != 9 { return 3 }
  0
}
## @align(4): b sits at byte 4 (1 rounded up), c at byte 8
takeal := fn(p : Al) -> u64 {
  if u64(p.a) != 10 { return 4 }
  if u64(p.b) != 100000 { return 5 }
  if u64(p.c) != 7 { return 6 }
  0
}
## @endian(big): v round-trips through the swap; the native-order overlays see the reversed bytes
takeen := fn(a : W32) -> u64 {
  if u64(a.v) != 287454020 { return 7 }        ## 0x11223344 round-trips (bswap out + in)
  if u64(a.raw) != 1144201745 { return 8 }     ## 0x44332211 — the raw stored bytes, little-endian
  if u64(a.b0) != 17 { return 9 }              ## byte 0 = 0x11, the HIGH byte of the big-endian value
  if u64(a.b3) != 68 { return 10 }             ## byte 3 = 0x44, the LOW byte
  0
}

main := fn() -> u64 {
  r := Reg(hi = 11, lo = 42, tail = 9)
  p := Al(a = 10, b = 100000, c = 7)
  w := W32(v = 287454020)
  e1 := takeoff(r)
  if e1 != 0 { return e1 }
  e2 := takeal(p)
  if e2 != 0 { return e2 }
  e3 := takeen(w)
  if e3 != 0 { return e3 }
  42
}
