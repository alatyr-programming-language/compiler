## Issue #764 — a signed `/` or `%` whose dividend is a LITERAL-ONLY expression divided UNSIGNED. Each
## dividend below is a comptime number with no name and no record of its own at the operand, so the
## legacy shape query answered "not provably signed" and selected the unsigned divide: `(0 - 7) % 9`
## returned 0, the remainder of the two's-complement bits `(2^64 - 7) mod 9`, where -7 is due.
## Spec v1.6.0 Concurrency §6.5: "the guard an operation carries is chosen by the operand types and by
## nothing else … An operand that *arrives* from a negation, a cast, a call or a load does not make the
## operation signed — the shape of the subexpression is not a type". Types §2.3: a comptime number is
## materialized into a fixed-width block in its context type, so `(0 - 7)` in an `i64` context is -7 and
## truncating `/` and `%` take the dividend's sign.
## Measured with each tree's own frozen seed (0.2.21 at c00eae90, 0.2.14 at 442472e5) on native x86_64,
## aarch64 and riscv64 under qemu and wasm under wasmtime: 42 on all four backends at c00eae90; WRONG on
## x86_64 at 442472e5 (the parent of `d3e968f1`, the slice-1 step e3 commit that moved x86's signedness
## queries onto sema's record) — this program answered 0 there, every check failing, while all three twins
## already answered 42.
main := fn() -> u64 {
  q : i64 = (0 - 7) % 9
  r : i64 = (0 - 42) / 9
  s : i64 = ((0 - 42) / 9) % 5
  mut ok : u64 = 0
  if q == (0 - 7) { ok = ok + 14 }
  if r == (0 - 4) { ok = ok + 14 }
  if s == (0 - 4) { ok = ok + 14 }
  ok
}
## expect: run 42
