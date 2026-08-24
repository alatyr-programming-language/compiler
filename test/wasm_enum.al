Color := enum { Red, Green, Blue }
main := fn() -> u64 {
  c := Color.Blue
  match c {
    Color::Red => 1
    Color::Green => 2
    Color::Blue => 42
  }
}
