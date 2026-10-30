main := fn() -> u64 {
  mut i := 0
  while i < 42 { i = i + 1 }
  return i
}
## expect(aarch64): run 42
## expect(riscv64): run 42
## expect(wasm): run 42
