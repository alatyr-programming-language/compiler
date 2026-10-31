main := fn() -> u64 {
  x := 40
  y := 2
  return x + y
}
## expect(aarch64): run 42
## expect(riscv64): run 42
## expect(wasm): run 42
