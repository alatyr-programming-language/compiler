main := fn() -> u64 { return if (1 < 2) and (5 > 3) { 42 } else { 0 } }
## expect(aarch64): run 42
## expect(riscv64): run 42
## expect(wasm): run 42
