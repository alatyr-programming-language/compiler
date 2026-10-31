Color := enum { Red, Green, Blue }
main := fn() -> u64 {
  c := Color.Blue
  match c {
    Color::Red => 1
    Color::Green => 2
    Color::Blue => 42
  }
}
## expect(aarch64): run 42
## expect(riscv64): run 42
## expect(wasm): run 42
