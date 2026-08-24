## e2e — §2 item 3: a built-in-INTEGER comparison desugars to cmp.al's `lt`/`eq` (`operator_decl_idx`
## / `cmp_route_idx`). With a local `@inline lt(u64)`, `a > b` routes as `lt(b, a)` (operand swap).
## 100 > 50 -> lt(50,100) -> true -> 42. Exercises the swap desugar + unsigned `setb` lowering.
@inline lt := fn(a : u64, b : u64) -> bool {
  mut out : bool = false
  comptime if target.arch == Arch.x86_64 { x86_64.setb(out, a, b) }
  return out
}
main := fn() -> u64 {
  a : u64 = 100
  b : u64 = 50
  if a > b { 42 } else { 0 }
}
