main := fn() -> u64 {
  comptime value : u64 = 5
  comptime enabled := true
  comptime if enabled {
    return value + 37
  } else {
    return 0
  }
  return 0
}
