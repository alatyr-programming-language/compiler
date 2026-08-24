## A module-level immutable str binding is a compile-time value. Its bytes view must
## behave exactly like indexing the equivalent string literal.
ALPHABET := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

b64_char := fn(v : u64) -> u8 {
  bytes(ALPHABET)[usize(v)]
}

literal_char := fn(v : u64) -> u8 {
  bytes("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")[usize(v)]
}

main := fn() -> u64 {
  if b64_char(0) != literal_char(0) { return 1 }
  42
}
