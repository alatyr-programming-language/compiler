main := fn() -> u64 {
  mut x : u64 = 0
  return zzz + x
}
## expect: reject "check: invalid at line 3 in reject_sema_line_3"
