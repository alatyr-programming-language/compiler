main := fn() -> u64 {
  print("a")
  print("b")
  println("c")
  return 42
}
## expect(aarch64): run 42
## expect(riscv64): run 42
## expect(wasm): run 42
