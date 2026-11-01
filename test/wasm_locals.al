main := fn() -> u64 {
  x : u64 = 40
  y : u64 = 2
  return x + y
}
## expect(aarch64): run 42
## expect(riscv64): run 42
## expect(wasm): run 42
