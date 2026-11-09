## e2e — issue #1416: a FIELD READ on a local whose type is a user `brand` over a kernel block `bits64`.
## A `bitsN` block is a raw scalar word (Types §2), and a brand over it keeps that representation (Types
## §5.4). Measured on the parent (main 879c02eb, native x86_64): check 0, build 0, and the program answered
## a fabricated 0.
B := brand(bits64)
main := fn() -> u64 {
  i : B = B(3)
  u64(bitcast(bits64, i.a))
}
## expect: reject "a scalar has no field to name at line 8 in issue1416_brand_field_bits"
