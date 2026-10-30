sq := fn(x : u64) -> u64 { return x * x }
main := fn() -> u64 { return sq(6) + 6 }
## expect(aarch64): run 42
## expect(riscv64): run 42
## expect(wasm): run 42
