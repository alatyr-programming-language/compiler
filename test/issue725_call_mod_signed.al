## Issue #725 — the `%` twin: a negative CALL result modulo 8 is -5 (signed); the three non-x86 backends
## answered the unsigned remainder 3 (exit 103) on the parent. Found by `scripts/progen.py` (seed 6).
progen_trigger := fn() -> u64 {
  match checked_add(u8(1), u8(1)) { Some(v) => { u64(v) } None => { 0 } }
}
f6 := fn(p7 : i64) -> i64 { return p7 }
main := fn() -> u64 {
  v : i64 = unchecked (f6(0 - 245) % 8)
  if v == (0 - 5) { return 42 }
  return u64(unchecked (v + 100))
}
