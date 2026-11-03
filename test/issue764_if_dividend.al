## Issue #764 — a signed `/` or `%` whose dividend is an `if` EXPRESSION divided UNSIGNED. The shape
## query recognised a bare typed name and nothing else, so an `if` value arriving in the operand fell to
## the emitter's unsigned default: `(if v < 0 { v } else { 5 }) % 9` with `v = -2 : i64` answered 5 —
## the remainder of the positive branch's value, because `(2^64 - 2) mod 9 = 5` — where -2 is due. The
## third line puts an `if` on BOTH sides of the operator, so neither operand's spelling can carry the
## answer. Spec v1.6.0 Concurrency §6.5: "the guard an operation carries is chosen by the operand types
## and by nothing else … the shape of the subexpression is not a type"; §3.2 (Types): signedness lives
## in the operations, and the interpretation of the operands selects the instruction.
## Measured with each tree's own frozen seed (0.2.21 at c00eae90, 0.2.14 at 442472e5) on native x86_64,
## aarch64 and riscv64 under qemu and wasm under wasmtime: 42 on all four backends at c00eae90; WRONG on
## x86_64 at 442472e5 (the parent of `d3e968f1`, slice-1 step e3) — this program answered 0 there, every
## check failing, while all three twins already answered 42.
main := fn() -> u64 {
  v : i64 = 0 - 2
  n : i64 = 9
  q : i64 = (if v < 0 { v } else { 5 }) % 9
  w : i64 = 0 - 42
  r : i64 = (if w < 0 { w } else { 5 }) / 9
  s : i64 = (if w < 0 { w } else { 5 }) % (if n > 0 { n } else { 1 })
  mut ok : u64 = 0
  if q == (0 - 2) { ok = ok + 14 }
  if r == (0 - 4) { ok = ok + 14 }
  if s == (0 - 6) { ok = ok + 14 }
  ok
}
## expect: run 42
