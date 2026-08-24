Color := enum { Red, Green, Blue }
mut STATE := Color.Blue
main := fn() -> u64 {
  match STATE {
    Color::Red => 1
    Color::Green => 2
    Color::Blue => 42
  }
}
