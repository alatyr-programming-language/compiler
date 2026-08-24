## e2e (reject) — the VALUE-position twin of `reject_attr_endian_prefix.al`, pinning the loud answer
## that has always been correct here so the two spellings can never drift apart again (Types §8).
S := @endian(big) struct { a : u32 }
main := fn() -> u64 {
  s := S(a = 1)
  return u64(s.a)
}
