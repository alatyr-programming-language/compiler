## e2e — issue #1416: a FIELD READ on an owner whose type is a user `brand` over a scalar (`Id := brand(u64)`).
## A brand changes identity, never representation (Types §5.4), and fields belong to products (Types §6.1),
## so `i.a` names nothing. Measured on the parent (main 879c02eb, native x86_64): check 0, build 0, and the
## program answered a fabricated 0.
Id := brand(u64)
main := fn() -> u64 {
  i : Id = Id(3)
  u64(i.a)
}
## expect: reject "a scalar has no field to name at line 8 in issue1416_brand_field_tail"
