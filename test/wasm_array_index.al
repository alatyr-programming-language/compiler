main := fn() -> u64 {
  a := [10, 20, 12]
  mut s : u64 = 0
  mut i := 0
  while i < 3 { s = s + a[i]
    i = i + 1 }
  return s
}
## expect(aarch64): run 42
## expect(riscv64): run 42
## expect(wasm): run 42
