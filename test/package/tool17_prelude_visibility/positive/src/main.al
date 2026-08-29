## Positive control: published target projections remain usable from ordinary source.
main := fn() -> u64 {
  mut x : u64 = 0
  comptime if target.kind == Kind.executable { x = x + 20 } else { x = x + 200 }
  comptime if target.code_size == CodeSize.b64 { x = x + 22 } else { x = x + 220 }
  return x
}
