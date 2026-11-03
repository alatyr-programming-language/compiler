## Issue #764 — a signed `/` or `%` whose dividend is a `match` value: a PAYLOAD BINDING (the shape the
## issue's 2026-09-30 progen comment added, "a payload binding is a bare name, but it has no declared
## type span") and the whole `match` EXPRESSION result. Both fell to the emitter's unsigned default on
## the three twins: `y / 9` with `y` an `i64` payload binding of -42 divided the bits `(2^64 - 42)` by 9,
## a huge positive, so no check matched and the program exited 0 where the signed -4 gives 42. Spec v1.6.0
## Concurrency §6.5: the signedness comes from the operand TYPE, and a payload binding's type is the
## variant's declared payload type (Types §5, §3.2) — nothing about how the binding was introduced enters
## into it.
## Measured with each tree's own frozen seed (0.2.21 at c00eae90, 0.2.16 at 33a0e6b5, 0.2.14 at
## 442472e5) on native x86_64, aarch64 and riscv64 under qemu and wasm under wasmtime: 42 on all four
## backends at c00eae90; WRONG on all three twins at 33a0e6b5 (the parent of `09dad599`, "twins: / % take
## their signedness from sema's record") — aarch64, riscv64 and wasm each answered 0 there while x86_64
## answered 42, emitting `udiv` / `divu` / `i64.div_u`; and WRONG on all four at 442472e5 (the parent of
## `d3e968f1`, slice-1 step e3).
E := enum { A(i64), B(i64, i64) }
main := fn() -> u64 {
  n : i64 = 0 - 42
  e : E = E.B(1, n)
  q : i64 = match e { E::A(x) => { 0 } E::B(x, y) => { y / 9 } }
  r : i64 = match e { E::A(x) => { 0 } E::B(x, y) => { y % 9 } }
  s : i64 = (match e { E::A(x) => { x } E::B(x, y) => { y } }) / 9
  mut ok : u64 = 0
  if q == (0 - 4) { ok = ok + 14 }
  if r == (0 - 6) { ok = ok + 14 }
  if s == (0 - 4) { ok = ok + 14 }
  ok
}
## expect: run 42
