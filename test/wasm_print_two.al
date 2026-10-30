main := fn() -> u64 {
  x := 40
  print("{} and {}", x, 2)
  return 42
}
## expect(aarch64): run 42
## expect(riscv64): run 42
## expect(wasm): run 42
