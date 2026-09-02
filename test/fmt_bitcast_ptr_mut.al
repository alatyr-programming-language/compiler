## e2e/fmt — a SUB-WORD pointer bitcast keeps the complete target type, including the `mut` marker
## the source wrote. The parser preserves `ptr([mut] u8)` as one target span, so formatting can emit
## the same pointer surface and a reparse retains the pointer-specific deref width.
##
## Both spellings appear below so a fix cannot pass by simply ALWAYS writing `mut`: `wp` is written
## `ptr(mut u8)` and must come back with the marker, `rp` is written `ptr(u8)` and must come back
## without it. Behaviour is identical either way — the `fmt-has` needles are the real assertion.
main := fn() -> u64 {
  mut cell : u64 = 0
  addr := unchecked bitcast(usize, ptr(mut cell))
  wp := unchecked bitcast(ptr(mut u8), addr)
  deref(wp) = 42
  rp := unchecked bitcast(ptr(u8), addr)
  if u64(deref(rp)) != 42 { return 1 }
  u64(deref(rp))
}
