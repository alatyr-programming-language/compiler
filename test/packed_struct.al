## §8 @packed byte-precise struct layout (spec Types §8). A packed struct removes padding:
## fields at natural byte offsets, alignment 1, size = sum of field byte sizes. Here
## a:u8@0, b:u16@1, c:u32@3, d:u64@7 → total 15 bytes (word-sized would be 32, offsets 0/8/16/24).
## Constructed with sized stores, read back with sized loads; the values (b=300 needs 2 bytes,
## c=100000 needs 4) would corrupt under a truncated load, so a correct read is proven. Returns 42.
Point := @packed struct { a : u8, b : u16, c : u32, d : u64 }

main := fn() -> u64 {
  p := Point(a = 10, b = 300, c = 100000, d = 7)
  ## observable packing: size is the byte sum 15, not words*8 = 32
  if size(Point) != 15 { return 1 }
  ## sized reads: each field's full value survives (no cross-field bleed / truncation)
  if u64(p.a) != 10 { return 2 }
  if u64(p.b) != 300 { return 3 }
  if u64(p.c) != 100000 { return 4 }
  if p.d != 7 { return 5 }
  mut sum := u64(p.a) + u64(p.b) + u64(p.c) + p.d
  if sum != 100317 { return 6 }
  return 42
}
