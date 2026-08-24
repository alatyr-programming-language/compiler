## §8 @endian(big) — big-endian field byte order (spec Types §8; wire formats), extending the @packed
## byte-precise layout. On the little-endian x86 native, a `@endian(big)` scalar field STORES its bytes
## MSB-first (byte-reversed, a `bswap`/`rolw` sized to the field width) and LOADS them back reversed —
## so it round-trips to the native value while the RAW stored bytes are observably byte-swapped.
##
## The swap is observed by overlaying NATIVE-order reads (`@offset`) on the same bytes: a native u32/u16
## read of a big-endian field yields the byte-SWAPPED integer, and reading byte 0 yields the HIGH byte
## of the big-endian value (byte 0 in memory is the MSB). Only the big-endian field is constructed; the
## overlay fields are unwritten aliases (partial construction), so they read the big-endian field's bytes.
## A wrong or SILENTLY-IGNORED swap would leave the raw bytes un-reversed and fail these checks. Returns 42.
W32 := @packed struct { @endian(big) v : u32, @offset(0) raw : u32, @offset(0) b0 : u8, @offset(3) b3 : u8 }
W16 := @packed struct { @endian(big) v : u16, @offset(0) raw : u16, @offset(0) b0 : u8, @offset(1) b1 : u8 }

main := fn() -> u64 {
  a := W32(v = 287454020)                   ## 0x11223344, stored big-endian as bytes [11 22 33 44]
  if u64(a.v) != 287454020 { return 1 }      ## round-trips through its own big-endian load (bswap out+in)
  if u64(a.raw) != 1144201745 { return 2 }   ## 0x44332211 — the raw stored bytes read little-endian (swapped)
  if u64(a.b0) != 17 { return 3 }            ## byte 0 = 0x11, the HIGH byte of the big-endian value
  if u64(a.b3) != 68 { return 4 }            ## byte 3 = 0x44, the LOW byte

  b := W16(v = 4386)                         ## 0x1122, stored big-endian as bytes [11 22]
  if u64(b.v) != 4386 { return 5 }           ## round-trips (rolw $8 out+in)
  if u64(b.raw) != 8721 { return 6 }         ## 0x2211 — swapped 16-bit read
  if u64(b.b0) != 17 { return 7 }            ## byte 0 = 0x11 (high byte)
  if u64(b.b1) != 34 { return 8 }            ## byte 1 = 0x22 (low byte)
  return 42
}
