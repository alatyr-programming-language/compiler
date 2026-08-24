## e2e — `size([T; N])` ARRAY-TYPE literal as a comptime builtin argument (Types §6.4): the byte size
## of the array TYPE is `N × stride(T)` (lean word model: stride = the element type's size). Was a
## silent-wrong / unbound pair: `size([u64; 3])` read `u64` as an unbound name, and `[Rec; 2].size()`
## folded to the scalar default 8 (not 16). Now folds (direct call + UFCS, fill + comma form, scalar +
## declared-struct elements, `[T; 0]`/`[]` → 0). Returns 42 iff every observed size matches.
Rec := struct { a : u64, b : u64 }

main := fn() -> u64 {
  s1 := size([u64; 3])            ## 24 = 3 × 8
  s2 := size([u8; 4])             ## 4 = 4 × 1
  s3 := size([Rec; 2])            ## 32 = 2 × 16 (Rec is a 2-word struct)
  s4 := size([u64; 0])            ## 0 (zero-sized, §6.5)
  s5 := size([])                  ## 0 (empty array literal)
  s6 := [u64; 3].size()           ## 24 (UFCS on the array-type literal)
  s7 := [Rec; 2].size()           ## 32 (UFCS)
  s8 := size([u64, u64, u64])     ## 24 (comma form)
  s9 := size([Rec; 1])            ## 16 (struct-element stride = size(Rec))
  s10 := size([u8; 0])            ## 0 (zero elements even for byte-sized element types)
  s11 := [u8; 0].size()           ## 0 (UFCS on a zero-size byte array type)
  ok := (s1 == 24) and (s2 == 4) and (s3 == 32) and (s4 == 0) and (s5 == 0) and (s6 == 24) and (s7 == 32) and (s8 == 24) and (s9 == 16) and (s10 == 0) and (s11 == 0)
  if ok { 42 } else { 1 }
}
