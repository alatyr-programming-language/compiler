add := fn(a : u64, b : u64) -> u64 { return a + b }
main := fn() -> u64 { return add(40, 2) }
## expect(aarch64): run 42
## expect(riscv64): run 42
## expect(wasm): run 42
