## BYTES negative: a statically provable index into a zero-length fixed array must be rejected by the
## shared semantic check before any backend emits code. The `[u8; 0]` type and zero-fill initializer
## remain legal; only the `xs[0]` access is invalid.
main := fn() -> u64 {
  xs : [u8; 0] = [0; 0]
  xs[0]
}
