## e2e (#1283) - the field store through comptime arithmetic: `s.f = 200 + 100` into `f : u8` is the
## exact sum 300, outside `u8`, and fails where it is written (Comptime §2.6) as the initializer form
## does. Measured on main `aab6ce1a`: check rc 0, run rc 7 - the field held 44.
S := struct { f : u8 }

main := fn() -> i64 {
  mut s := S(f = 1)
  s.f = 200 + 100
  u64(s.f)
}
## expect: reject "comptime overflow" "at line 8"
