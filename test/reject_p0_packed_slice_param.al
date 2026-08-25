## P0 / Types §8: a `Slice(P)` parameter keeps the declared `@packed` element type.
## The non-x86 aggregate-slice path is word-strided and cannot represent P's byte-precise
## element stride, so it must reject before emitting rather than silently miscompile `s[i]`.
P := @packed struct { a : u8, b : u32 }

read := fn(s : Slice(P)) -> u64 {
  return u64(s[0].a) + u64(s[0].b)
}

main := fn() -> u64 {
  s := Slice(P)(ptr = unchecked bitcast(ptr(P), 0), len = 0)
  return read(s)
}
