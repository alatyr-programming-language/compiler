## e2e — issue #1416: a FIELD READ on a PARAMETER whose type is a user `brand` over a scalar.
## A brand keeps the representation of the type it brands (Types §5.4), and a scalar has no fields (Types
## §6.1). Measured on the parent (main 879c02eb, native x86_64): check 0, build 0, and the program answered
## a fabricated 0.
Id := brand(u64)
get := fn(k : Id) -> u64 {
  u64(k.a)
}
main := fn() -> u64 {
  get(Id(3))
}
## expect: reject "a scalar has no field to name at line 7 in issue1416_brand_field_param"
