## e2e — issue #1416: a FIELD READ on an annotated MODULE GLOBAL whose type is a user `brand` over a scalar.
## A brand keeps the representation of the type it brands (Types §5.4), and a scalar has no fields (Types
## §6.1). Measured on the parent (main 879c02eb, native x86_64): check 0, build 0, and the program answered
## a fabricated 0.
Id := brand(u64)
G : Id = Id(3)
main := fn() -> u64 {
  u64(G.a)
}
## expect: reject "a scalar has no field to name at line 8 in issue1416_brand_field_global"
