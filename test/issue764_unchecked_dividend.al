## Issue #764 — a signed `/` or `%` whose dividend is an `unchecked` arithmetic expression divided
## UNSIGNED. `unchecked` drops the checked-overflow guard of Concurrency §6.1 to hardware behaviour
## (§6.2) and nothing else: it does not change the operand's TYPE, so the divide stays signed. The
## legacy shape query saw an `unchecked` node rather than an `i64` and chose the unsigned divide:
## `unchecked (v - w) / 2` with `v = 3, w = 5 : i64` answered 9223372036854775807 — `(2^64 - 2) / 2`
## — where -1 is due. Spec v1.6.0 Concurrency §6.5: the guard and the signedness follow "the operand
## types and by nothing else"; §6.2 lists exactly what `unchecked` drops (division by zero, an
## over-width shift, `MIN ÷ -1`, `MIN % -1`) and signedness is not among it.
## Measured with each tree's own frozen seed (0.2.21 at c00eae90, 0.2.14 at 442472e5) on native x86_64,
## aarch64 and riscv64 under qemu and wasm under wasmtime: 42 on all four backends at c00eae90; WRONG on
## x86_64 at 442472e5 (the parent of `d3e968f1`, slice-1 step e3) — this program answered 0 there, every
## check failing, while all three twins already answered 42.
main := fn() -> u64 {
  v : i64 = 3
  w : i64 = 5
  q : i64 = (unchecked (v - w)) / 2
  r : i64 = (unchecked (v - w)) % 7
  s : i64 = unchecked ((0 - 42) / 9)
  mut ok : u64 = 0
  if q == (0 - 1) { ok = ok + 14 }
  if r == (0 - 2) { ok = ok + 14 }
  if s == (0 - 4) { ok = ok + 14 }
  ok
}
## expect: run 42
