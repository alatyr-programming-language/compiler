## CG-13: a user-provided routed native-integer operator cannot bypass the operation-site guard.
## The raw `addl` body intentionally wraps u32, but checked `MAX + 3` must trap before that body runs;
## this is the non-stdlib companion to the base::num routed narrow regression.
@inline + := fn(a : u32, b : u32) -> u32 {
  mut out : u32 = a
  comptime if target.arch == Arch.x86_64 { x86_64.addl(out, b) }
  return out
}
main := fn() -> u64 {
  a : u32 = 4294967295
  b : u32 = 3
  u64(a + b)
}
