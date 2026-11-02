main := fn() -> u64 {
  mut r : u64 = 0
  if 3 < 5 { r = 42 } else { r = 1 }
  return r
}
## expect(aarch64): run 42
## expect(riscv64): run 42
## expect(wasm): run 42
