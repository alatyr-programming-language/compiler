## e2e — scalar FIELD write of a LOCAL struct-array element (`arr[i].b = v`, word 1 not word 0). Already
## correct via `emit_idx_field_addr` (element base +field_offset); a locking guard that word 1 is written
## and the neighbour element stays intact.
Rec := struct { a : i64, b : i64 }
main := fn() -> u64 {
  mut arr : [Rec; 4] = [Rec(a = 10, b = 0), Rec(a = 5, b = 0), Rec(a = 0, b = 0), Rec(a = 0, b = 0)]
  mut i := 1
  arr[i].b = 27
  u64(arr[1].a + arr[1].b + arr[0].a)   ## 5 + 27 + 10 = 42 (arr[0] untouched)
}
