## e2e (reject) — the same 64-bit ceiling holds in every base of Grammar §2.4, not just decimal:
## `0x1FFFFFFFFFFFFFFFF` is 2^65-1. Located reject, never a truncation or a compiler SIGILL.
main := fn() -> u64 {
  x : u64 = 0x1FFFFFFFFFFFFFFFF
  return x
}
