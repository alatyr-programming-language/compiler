## Types §9.4: the deep analog — a nested leaf `s.a.x` written on only ONE branch is NOT
## definitely-assigned after the join; reading it post-join is rejected.
Inner := struct { x : u64, y : u64 }
S := struct { a : Inner, b : Inner }
main := fn() -> u64 {
  mut s : S
  if true { s.a.x = 1 } else { s.a.y = 2 }
  return s.a.x
}
