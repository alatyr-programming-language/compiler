## e2e — one scalar-width matrix shared by parser, fmt, and packed layout.
##
## The sub-word rows cover unsigned/signed/bits 8/16/32, bool, char, and f32. The word rows cover
## the native integer/float widths and a pointer; `NarrowBrand` and `Aggregate` exercise the
## classifier's unknown-name/aggregate fallback without changing their established layout.
##
## The pointer probes use one word with high bits set. A lost `ptr(bitsN)` preservation would read the
## whole word instead of the 1/2/4-byte low part, while fmt would also erase the cast on reformat.
NarrowBrand := brand(u8)
Aggregate := struct { value : u8 }

Widths := @packed struct {
  u8v : u8, i8v : i8, b8v : bits8, boolv : bool,
  u16v : u16, i16v : i16, b16v : bits16,
  u32v : u32, i32v : i32, b32v : bits32, charv : char, f32v : f32
}

Words := @packed struct {
  uv : u64, iv : i64, usv : usize, isv : isize, fv : f64, pv : ptr(u8), brandv : NarrowBrand, agg : Aggregate
}

main := fn() -> u64 {
  mut cell : u64 = 4294967338
  addr := unchecked bitcast(usize, ptr(mut cell))
  p8 := unchecked bitcast(ptr(bits8), addr)
  p16 := unchecked bitcast(ptr(bits16), addr)
  p32 := unchecked bitcast(ptr(bits32), addr)
  if u64(deref(p8)) != 42 { return 1 }
  if u64(deref(p16)) != 42 { return 2 }
  if u64(deref(p32)) != 42 { return 3 }
  if size(Widths) != 30 { return 4 }
  if align(Widths) != 1 { return 5 }
  if size(Words) != 64 { return 6 }
  if align(Words) != 1 { return 7 }
  return 42
}
