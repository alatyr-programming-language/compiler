## §8 @repr(T) — the NARROW in-memory tag STORE (spec Types §8). `emit_enum_assign` writes a
## @repr(i32) enum's discriminant with `movl` (4 bytes), not `movq` (8) — the STORE dual of the
## already-narrow `emit_repr_tag_load`. This test OBSERVES the store width: it takes the address of
## the enum local, seeds a sentinel in the 4 bytes just PAST the i32 tag (the upper half of the tag
## word), then REASSIGNS the enum (a second `emit_enum_assign`). A correct narrow `movl` store writes
## ONLY the low 4 bytes, leaving the sentinel intact; the former over-wide `movq` would have zeroed
## it. Correct → the tag reads back Blue (20) AND the sentinel survives (+22) = 42; a wide store → 20.
Color := @repr(i32) enum { Red, Green, Blue }

main := fn() -> u64 {
  mut c := Color.Red
  ## address of c's tag word: byte 0 = tag low byte, bytes [4..8) = the tag word's upper half
  base := unchecked bitcast(usize, ptr(c))
  hi := unchecked bitcast(ptr(mut u32), base + 4)
  ## seed the 4 bytes just past the i32 tag with a sentinel
  unchecked { deref(hi) = 3735928559 }               ## 0xDEADBEEF
  ## reassign — a NARROW (movl) i32 tag store to bytes [0..4); MUST NOT touch bytes [4..8)
  c = Color.Blue
  after := unchecked deref(hi)
  mut tag := 0
  match c {
    Color.Red => { tag = 100 }
    Color.Green => { tag = 100 }
    Color.Blue => { tag = 20 }
  }
  mut acc := tag
  if after == 3735928559 { acc = acc + 22 }
  acc
}
