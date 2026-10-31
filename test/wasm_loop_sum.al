sum := fn(n : u64) -> u64 {
  mut acc : u64 = 0
  mut i : u64 = 0
  while i < n { acc = acc + i
    i = i + 1 }
  return acc
}
main := fn() -> u64 { return sum(9) }
## expect(aarch64): run 36
## expect(riscv64): run 36
## expect(wasm): run 36
