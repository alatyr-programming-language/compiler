main := fn() -> u64 {
  mut x : u64 = 0
  return x +
    zzz
}
## expect: reject "check: invalid at line 4 in reject_sema_line_4"
