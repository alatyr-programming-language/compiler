pub probe := fn() -> u64 {
  mut x : u64 = 0
  comptime if target.kind == Kind.static_lib { x = 20 } else { x = 200 }
  comptime if target.kind != Kind.object { x = x + 22 } else { x = x + 200 }
  return x
}
