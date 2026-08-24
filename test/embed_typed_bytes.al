## BYTES: embed has the spec-facing [u8; N] surface, not only the internal str view.
## The compiler may reuse the binary-safe byte representation, but an explicit [u8; 4]
## binding must type-check, preserve the exact length, and expose byte indexing.
main := fn() -> u64 {
  b : [u8; 4] = embed("test/embed_fixture.bin")
  if b.len != 4 { return 1 }
  if u64(bytes(b)[0]) != 0 { return 2 }
  if u64(bytes(b)[1]) != 255 { return 3 }
  if u64(bytes(b)[2]) != 65 { return 4 }
  if u64(bytes(b)[3]) != 10 { return 5 }
  return 42
}
