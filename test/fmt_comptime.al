main := fn() -> u64 {
  s : u64 = 0
  comptime for i in 0 .. 3 {
    s = s + i
  }
  return s + 39
}
## expect(x86_64): run 42
