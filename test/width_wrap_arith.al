## e2e — §4 width-typed arithmetic WRAP via §2 operator routing inside an explicit `unchecked` scope:
## a typed `u32` operand routes to the `@inline u32 +` (x86_64 `addl`, a 32-bit truncating add), so
## `u32 MAX + 3` wraps to 2 (not the 64-bit 4294967298). Checked routing is covered by
## `checked_custom_routed_narrow`; this case confirms the raw route remains available under `unchecked`.
@inline + := fn(a : u32, b : u32) -> u32 {
  mut out : u32 = a
  comptime if target.arch == Arch.x86_64 { x86_64.addl(out, b) }
  return out
}
main := fn() -> u64 {
  a : u32 = 4294967295
  b : u32 = 3
  c : u32 = unchecked { a + b }
  u64(c)
}
