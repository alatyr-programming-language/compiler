## e2e — §2 operator overloading where the operator has a STATEMENT body (a `mut` local + a
## `comptime if arch { intrinsic }` + a trailing `return <StructLit>`, the num.al operator shape) AND
## returns the user type. The inline expander sets the struct return convention so each `return`
## delivers the result words via `emit_struct_value`, pushed at inline-end. (30,5)+(10,-3)=(40,2); 42.
Vec2 := struct { x : u64, y : u64 }
@inline + := fn(a : Vec2, b : Vec2) -> Vec2 {
  mut rx : u64 = a.x
  comptime if target.arch == Arch.x86_64 { x86_64.addq(rx, b.x) }
  mut ry : u64 = a.y
  comptime if target.arch == Arch.x86_64 { x86_64.addq(ry, b.y) }
  return Vec2(x = rx, y = ry)
}
main := fn() -> u64 {
  p := Vec2(x = 30, y = 5)
  q := Vec2(x = 10, y = -3)
  r := p + q
  r.x + r.y
}
