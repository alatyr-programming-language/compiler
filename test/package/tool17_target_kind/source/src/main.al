main := fn() -> u64 {
  mut x : u64 = 0
  comptime if target.kind == Kind.source { x = 42 } else { x = 7 }
  comptime if target.kind != Kind.executable { x = x + 0 } else { x = x + 100 }
  return x
}
