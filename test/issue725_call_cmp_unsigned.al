## Issue #725 — the comparison twin, in the other direction: a CALL returning `u64` compared with a `u64`
## above 2^63. `1 > 2^64 - 5` is false; the three non-x86 backends compared signed and answered 1 on the
## parent. Found by `scripts/progen.py` (seed 38).
progen_trigger := fn() -> u64 {
  match checked_add(u8(1), u8(1)) { Some(v) => { u64(v) } None => { 0 } }
}
f1 := fn() -> u64 { return 1 }
main := fn() -> u64 {
  big : u64 = unchecked (0 - 5)
  if f1() > big { return 1 }
  return 42
}
