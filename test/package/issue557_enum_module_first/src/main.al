C := aenum::C
main := fn() -> u64 {
  c : C = aenum::start()
  match c { R => { return 1 }; G => { return 2 } }
  return 0
}
