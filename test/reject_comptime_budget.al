main := fn() -> u64 {
  mut s : u64 = 0
  comptime for i in 0 .. 200000 { s = s + i }
  return s
}
