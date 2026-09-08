C := zenum::C
main := fn() -> u64 {
  c : C = zenum::start()
  match c { R => { return 1 }; G => { return 2 } }
  return 0
}
