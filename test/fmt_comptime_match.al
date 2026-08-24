knd := fn(T : type, v : T) -> u64 {
  comptime match typeinfo(T) {
    Struct => {
      return 1
    }
    _ => {
      return 42
    }
  }
}
main := fn() -> u64 {
  return knd(u64, 5)
}
