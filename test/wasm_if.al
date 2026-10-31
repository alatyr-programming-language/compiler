max := fn(a : u64, b : u64) -> u64 { return if a > b { a } else { b } }
main := fn() -> u64 { return max(42, 17) }
## expect(aarch64): run 42
## expect(riscv64): run 42
## expect(wasm): run 42
