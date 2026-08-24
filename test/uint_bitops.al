## e2e — ROADMAP TYP-10 slice: the BIT-glyph operators `&` / `|` / `^` on the prelude `u128 ≡
## uint(128)` (Types §3/§7, TYP-2 / TYP-10; operators.md OP-1). The three ops are `@inline` GENERIC
## per-word bitwise folds (lib/base/u128.al), used by BARE prelude name. A bit op is independent per
## lane — no carry, no cross-word ripple — so a correct route computes each word separately.
##
## `(a | b) & mask ^ c` (all three ops, left-assoc, same precedence → `(((a|b) & mask) ^ c)`) over
## two words, with `mask` selecting only the LOW word so the HIGH word must come out zero (a
## cross-word leak — the high word bleeding into the low, or a missed route folding scalar over the
## words — is caught by the `words[1] != 0` guard):
##   a    = [0x00F0, 0x00AA]
##   b    = [0x000F, 0x0055]
##   a|b  = [0x00FF, 0x00FF]
##   mask = [0x00FF, 0x0000]
##   &    = [0x00FF, 0x0000]
##   c    = [0x00D5, 0x0000]
##   ^    = [0x002A, 0x0000]   (0xFF ^ 0xD5 = 0x2A = 42)
## 42 = the low word of the result AND a zero high word; 1 = the high word leaked.
main := fn() -> u64 {
  a    := u128(words = [240, 170])
  b    := u128(words = [15, 85])
  mask := u128(words = [255, 0])
  c    := u128(words = [213, 0])
  z := (a | b) & mask ^ c
  if z.words[1] != 0 { return 1 }
  return z.words[0]
}
