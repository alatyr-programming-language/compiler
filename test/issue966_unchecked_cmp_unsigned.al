## e2e (#966, #969 — Types §4: an ordering over `u64` reads unsigned across 2^63).
## An ordering takes its signedness from sema's RECORD of the PAIR, as x86_64's `is_unsigned_cmp`
## already does. The twins' `*_cmp_unsigned` answered from their shape query alone, which proves nothing
## about an `Unchecked` node — so `1 > unchecked(u64 - u64)` took the SIGNED default and read
## 13835058055282163710 as negative, flipping the comparison to true. A silent wrong value on all three
## twins (progen seed 2074803688).
## Values: v24 = 2^62 + 3; 1 > (1 - v24) is FALSE unsigned, so the result is p22.k1 = 2.
S2 := struct { k1 : u64, k2 : u64 }
g10 := fn(p11 : u64, p12 : u64, p13 : S2) -> u64 { return 1 }
g21 := fn(p22 : S2, p23 : S2) -> u64 {
  mut v24 : u64 = (if 2147483648 < 1 { g10(3, 1, S2(k1 = 1, k2 = 3)) } else { 4611686018427387907 })
  return (if 1 > unchecked (p22.k2 - v24) { 1 } else { p22.k1 })
}
main := fn() -> u64 {
  mut acc : u64 = 0
  acc = unchecked ((acc * 31) ^ g21(S2(k1 = 2, k2 = 1), S2(k1 = 7, k2 = 100)))
  if acc != 2 { return 100 + acc }
  return 42
}
## expect: run 42
