first := fn() -> u64 { return 0 }
second := fn() -> u64 { return 0 }
main := fn() -> u64 {
  mut x : u64 = 0
  x = x + 1
  x = x + 1
  return zzz + x
}
## expect: reject "check: invalid at line 7 in reject_sema_line_7"
