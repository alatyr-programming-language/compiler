## Types §9.4: a field written on EVERY continuing branch IS definitely-assigned after the join.
## Companion accept-case to da_reject_field_join; returns 40.
S := struct { x : u64, y : u64 }
main := fn() -> u64 {
  mut s : S
  if true { s.x = 20 } else { s.x = 18 }
  return s.x * 2
}
