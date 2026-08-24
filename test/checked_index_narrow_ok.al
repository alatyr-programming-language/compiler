## Companion to checked_index_overflow (I11 / CG-6): a NON-overflowing narrow-width index add returns
## the correct value under the SAME element-type classification — 40 + 2 = 42 fits `u8`, so no trap.
## Confirms the CG-6 index-element-type recovery adds the per-width overflow check WITHOUT breaking an
## ordinary in-range narrow index add. x86-only (narrow arith is x86-only today).
main := fn() -> u64 {
  xs : [u8; 4] = [40, 2, 1, 2]
  i : u64 = 0
  j : u64 = 1
  return u64(xs[i] + xs[j])
}
