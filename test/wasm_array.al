main := fn() -> u64 {
  a := [40, 2]
  a[0] + a[1]
}
## expect(aarch64): run 42
## expect(riscv64): run 42
## expect(wasm): run 42
