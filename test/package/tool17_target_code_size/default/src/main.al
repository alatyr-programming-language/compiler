main := fn() -> u64 {
  mut x : u64 = 0
  comptime if target.code_size == CodeSize.b64 { x = 20 } else { x = 200 }
  comptime if target.code_size != CodeSize.b16 { x = x + 22 } else { x = x + 200 }
  return x
}
