## §8 @offset(N) — explicit field byte offset (spec Types §8; MMIO / register maps), extending the
## @packed byte-precise layout. In a @packed struct fields pack with no padding at a running byte
## cursor; a field carrying `@offset(N)` sits at byte N instead (and the cursor continues after it,
## overlap allowed — union-like / unchecked-flavored). Here `hi` and `lo` are BOTH placed at byte 0
## (an explicit overlap): the struct literal writes them in declaration order, so `lo` (written last)
## wins, and reading `hi` back yields `lo`'s value — 42, NOT the 11 it was constructed with. `tail`
## then sits at byte 4 (right after the overlapped u32), not at the word-sized slot. A wrong offset —
## or one silently ignored — reads the fields at the wrong bytes and returns a different value.
Reg := @packed struct { hi : u32, @offset(0) lo : u32, tail : u8 }

main := fn() -> u64 {
  r := Reg(hi = 11, lo = 42, tail = 9)
  ## byte-precise size: lo ends at byte 4, tail (byte 4) ends at byte 5 → 5 bytes (word-sized: 24).
  if size(Reg) != 5 { return 1 }
  ## overlap proof: hi and lo alias byte 0; lo written last, so hi reads 42, not its own 11.
  if u64(r.hi) != 42 { return 2 }
  if u64(r.lo) != 42 { return 3 }
  ## tail lives at byte 4 (immediately after the overlapped u32) and reads its own value.
  if u64(r.tail) != 9 { return 4 }
  return u64(r.hi)
}
