## e2e — issue #1416: a STORE through a field of an owner whose type is a user `brand` over a scalar.
## A brand changes identity, never representation (Types §5.4), and fields belong to products (Types §6.1),
## so `i.a = 4` names no place. Measured on the parent (main 879c02eb, native x86_64): check 0, build 0, and
## the program answered 3: the write was dropped.
Id := brand(u64)
main := fn() -> u64 {
  mut i : Id = Id(3)
  i.a = 4
  u64(i)
}
## expect: reject "a scalar has no field to name at line 8 in issue1416_brand_field_store"
