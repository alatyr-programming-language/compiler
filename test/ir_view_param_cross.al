## e2e — #1622: a `Slice(u64)` view crosses a call between the shared IR and the legacy emitter, in both
## directions, on every backend. `rd_lg` and `drv_lg` hold a float literal the IR does not build, so the
## legacy emitter emits them; `rd_ir`, `drv_ir` and `main` are IR-built. The view goes as the address of
## the caller's `{ptr, len}` pair (Types §7; Stdlib appendix §3.5: `ptr` at byte 0, `len` at byte 8),
## which every legacy emitter also passes, and a word element is one word apart on both sides (Types
## §6.4), so the crossing agrees. A narrower element does not cross on aarch64, riscv64 and wasm (their
## legacy emitters step a view by the word; `ir::sig_has_narrow_view`), and is not here.
## Exit 42 = all held; otherwise 100 + the mask of failed checks. Parent `9e60e8aa` built every function
## here with the legacy emitter (42 everywhere); this fixture guards the crossing the IR now makes.
rd_ir := fn(s : Slice(u64)) -> u64 {
  mut t : u64 = 0
  for x in s { t = t * 100 + x }
  t
}
rd_lg := fn(s : Slice(u64)) -> u64 {
  fz := 1.5
  mut t : u64 = 0
  for x in s { t = t * 100 + x }
  t
}
drv_lg := fn() -> u64 {
  fz := 1.5
  a : [u64; 3] = [7, 8, 9]
  mut m : u64 = 0
  if rd_ir(a[0..3]) != 70809 { m = m + 4 }
  if rd_ir(a[1..3]) != 809 { m = m + 8 }
  m
}
drv_ir := fn() -> u64 {
  a : [u64; 3] = [7, 8, 9]
  mut m : u64 = 0
  if rd_lg(a[0..3]) != 70809 { m = m + 1 }
  if rd_lg(a[1..3]) != 809 { m = m + 2 }
  if rd_ir(a[1..3]) != 809 { m = m + 16 }
  m
}
main := fn() -> u64 {
  m := drv_ir() + drv_lg()
  if m != 0 { return 100 + m }
  42
}
## expect: run 42
