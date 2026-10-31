main := fn() -> u64 {
  print("a\nb\nc")
  return 42
}
## expect(wasm): run 42
