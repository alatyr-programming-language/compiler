## TYP-13 runtime seam: the exact integer must be materialized as f32, not stored as integer bits.
main := fn() -> u64 {
  x : f32 = 16777216
  if u64(x) != 16777216 { return 1 }
  42
}
