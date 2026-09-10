pick := fn(c : ptr(C)) -> u64 {
  match deref(c) { R => { return 1 }; G => { return 2 } }
  return 0
}
main := fn() -> u64 {
  mut v := start()
  return pick(ptr(mut v))
}
