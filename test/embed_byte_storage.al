## P1-BYTES — an explicitly typed byte fixed-array backed by embed storage.
## Direct local/global indexing, byte addresses, mutation, and .len must all use [T; N].
mut EMBED_GLOBAL : [u8; 4] = embed("test/embed_fixture.bin")
EMBED_CONST : [u8; 4] = embed("test/embed_fixture.bin")

main := fn() -> u64 {
  local : [u8; 4] = embed("test/embed_fixture.bin")
  p0 := unchecked bitcast(usize, ptr(local[0]))
  p1 := unchecked bitcast(usize, ptr(local[1]))
  g0 := unchecked bitcast(usize, ptr(EMBED_GLOBAL[0]))
  g1 := unchecked bitcast(usize, ptr(EMBED_GLOBAL[1]))
  c0 := unchecked bitcast(usize, ptr(EMBED_CONST[0]))
  c1 := unchecked bitcast(usize, ptr(EMBED_CONST[1]))
  if p1 - p0 != 1 { return 1 }
  if g1 - g0 != 1 { return 2 }
  if c1 - c0 != 1 { return 7 }
  if local[0] != 0 or local[1] != 255 or local[2] != 65 or local[3] != 10 { return 3 }
  if EMBED_GLOBAL[0] != 0 or EMBED_GLOBAL[1] != 255 or EMBED_GLOBAL[2] != 65 or EMBED_GLOBAL[3] != 10 { return 4 }
  EMBED_GLOBAL[1] = 42
  if EMBED_GLOBAL[1] != 42 { return 5 }
  if EMBED_CONST[0] != 0 or EMBED_CONST[1] != 255 or EMBED_CONST[2] != 65 or EMBED_CONST[3] != 10 { return 6 }
  if local.len != 4 or EMBED_GLOBAL.len != 4 or EMBED_CONST.len != 4 { return 8 }
  return 42
}
