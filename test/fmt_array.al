main := fn() -> u64 {
  a : [u64; 3] = [40, 1, 1]
  return a[0] + a[1] + a[2]
}
## expect(x86_64): run 42
