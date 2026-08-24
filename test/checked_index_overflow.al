## Checked-mode NARROW-WIDTH overflow trap for an INDEX read (I11 / CG-6): `xs[i] + xs[j]` where
## `xs : [u8; N]` reads two u8 elements; 200 + 100 = 300 > 255 does not fit u8, so the checked guard
## TRAPS (x86 shr-check + ud2 -> exit 132) BEFORE the value-model wrap. Before CG-6 the element TYPE
## of an index read was unknown, so the sum classified as NATIVE-width and the narrow overflow was
## silently dropped. `expr_type_span` now recovers the element type from the array's declared
## `[u8; N]` (source-scan), so the operand is seen as `u8`. x86-only (narrow arith is x86-only today).
main := fn() -> u64 {
  xs : [u8; 4] = [200, 100, 1, 2]
  i : u64 = 0
  j : u64 = 1
  return u64(xs[i] + xs[j])
}
