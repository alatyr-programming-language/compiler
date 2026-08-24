## Types §9.4: a struct field written on only ONE branch of an if/else is NOT definitely-assigned
## after the join; reading it post-join reads uninitialized memory on the other path -> rejected.
S := struct { x : u64, y : u64 }
main := fn() -> u64 {
  mut s : S
  if true { s.x = 1 } else { s.y = 2 }
  return s.x
}
