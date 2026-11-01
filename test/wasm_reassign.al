main := fn() -> u64 {
  mut x : u64 = 10
  x = x * 4
  x = x + 2
  return x
}
## expect(aarch64): run 42
## expect(riscv64): run 42
## expect(wasm): run 42
