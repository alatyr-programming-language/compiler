## e2e (reject) — the base prefixes of Grammar §2.4 are the LOWERCASE terminals `"0x"` / `"0o"` /
## `"0b"`. The spec names both cases wherever it means both (`exp ::= ("e" | "E")`), so `0XFF` is
## not an Alatyr literal and must be rejected located rather than silently accepted.
main := fn() -> u64 {
  x : u64 = 0XFF
  return x
}
