## §8 a field carrying BOTH @endian AND @offset — in EITHER attribute order. The former single-adjacent
## backward scanners found only the attribute IMMEDIATELY before the field name and MISSED the other:
##   `@endian(big) @offset(0) v` : scanning back from `v` the ENDIAN scan hit @offset(0) first and missed
##                                 the big-endian swap (v stored/read native — a wrong-byte-order layout);
##   `@offset(8) @endian(big) w` : scanning back from `w` the OFFSET scan hit @endian first and missed the
##                                 explicit byte-8 placement (w landed at the running cursor instead).
## The chain walker skips a non-matching adjacent attribute and continues to find its own, so both levers
## fire on both fields. Values are constructed in declaration order (the constructor value list is
## POSITIONAL — the first two written fields are v, w); the observer/alias fields follow, unwritten, and
## read v's/w's raw bytes through native-order @offset overlays. Returns 42.
Both := @packed struct {
  @endian(big) @offset(0) v : u32,    ## field 0 (written) — byte 0, big-endian: offset scan must skip @endian
  @offset(8) @endian(big) w : u32,    ## field 1 (written) — byte 8, big-endian: endian scan must skip @offset
  @offset(0) vb0 : u8,                ## byte 0 of v = its MSB under big-endian (0x11)
  @offset(8) wb0 : u8,                ## byte 8 (start of w) = w's MSB under big-endian (0x11)
  @offset(0) vraw : u32,              ## native-order read of v's bytes (byte-swapped)
  @offset(8) wraw : u32               ## native-order read of w's bytes (byte-swapped)
}

main := fn() -> u64 {
  x := Both(v = 287454020, w = 287454020)   ## both 0x11223344, stored big-endian as bytes [11 22 33 44]
  ## v (@endian(big) @offset(0)) — the @offset is adjacent, the @endian is BEHIND it: proves the endian
  ## scan skipped @offset to see @endian, so v was byte-reversed on store.
  if u64(x.v) != 287454020 { return 1 }       ## round-trips through its own big-endian load (bswap out+in)
  if u64(x.vb0) != 17 { return 2 }            ## byte 0 = 0x11 (the MSB) — only true if the big-endian store fired
  if u64(x.vraw) != 1144201745 { return 3 }   ## 0x44332211 — the raw stored bytes read little-endian (swapped)
  ## w (@offset(8) @endian(big)) — the @endian is adjacent, the @offset is BEHIND it: proves the offset
  ## scan skipped @endian to see @offset(8), so w sits at byte 8 (not the running cursor 4).
  if u64(x.wb0) != 17 { return 4 }            ## byte 8 = 0x11 — big-endian MSB at the explicit offset
  if u64(x.wraw) != 1144201745 { return 5 }   ## 0x44332211 — swapped, read at byte 8
  return 42
}
