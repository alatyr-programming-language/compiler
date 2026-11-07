## e2e (#1499) — a `u64` `comptime for` upper bound of 2^63 or more is over the unroll budget and is
## REFUSED at compile time with a located diagnostic, never compiled to an empty loop.
##
## Comptime §2.2 (spec v1.8.0): a comptime evaluation yields a deterministic result or fails, and there
## are no silent partial results. Types §3.2 / Concurrency §6.5: the bound is a `u64`, so 2^63 + 1 is a
## large unsigned value, not a negative one. The budget test compared the bounds' `i64` patterns signed,
## so `hi - lo` was negative and passed it, and the signed `k < hi` walk unrolled nothing.
##
## Measured on the parent (`f9ca474d`, native x86_64, omen, Stage1 built by `seed/alatyr`): all four
## backends compiled it with rc 0 and ran to 7 (x86_64, aarch64 and riscv64 under qemu, wasm under
## wasmtime). Here x86_64 refuses at the bound; the twins trap at run time until #1232.
B : u64 = 9223372036854775809

main := fn() -> u64 {
  mut a : u64 = 0
  comptime for i in 0 .. B { a = a + 1 }
  return a + 7
}
## expect: reject "budget exhausted" "never a silent partial result. at line 16 in "
