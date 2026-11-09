## e2e — issue #1416: a TUPLE POSITION `.0` on an owner whose type is a user `brand` over a scalar.
## Types §6.1 gives `.N` to tuples only, and a brand keeps its underlying representation (Types §5.4).
## Measured on the parent (main 879c02eb, native x86_64): check 0 while build refused in the lower: the two
## surfaces disagreed.
Id := brand(u64)
main := fn() -> u64 {
  i : Id = Id(3)
  u64(i.0)
}
## expect: reject "a scalar has no field to name at line 8 in issue1416_brand_tuple_pos"
