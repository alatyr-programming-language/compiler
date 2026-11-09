## e2e — issue #1416: a FIELD READ on a PARAMETER whose type is a brand over a brand over a scalar.
## Each brand keeps the representation of the type it brands (Types §5.4), so the chain ends at a scalar,
## which has no fields (Types §6.1).
Id := brand(u64)
Key := brand(Id)
get := fn(k : Key) -> Id {
  k.a
}
main := fn() -> u64 {
  7
}
## expect: reject "a scalar has no field to name at line 7 in issue1416_brand_field_chain"
