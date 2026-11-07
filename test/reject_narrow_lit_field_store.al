## e2e (#1283) - a struct FIELD is a target place of Types §9.1 / Declarations §3.4 too: `s.f = 300`
## into `f : u8` was accepted and the field read back 44 (the silent wrap I11 forbids), while the
## initializer `S(f = 300)` of the same field was refused. Located at the store (line 11). Measured on
## main `aab6ce1a`: check rc 0, run rc 7 (`s.f == 44` held).
S := struct { f : u8 }

main := fn() -> i64 {
  mut s := S(f = 1)
  s.f = 255
  if u64(s.f) != 255 { return 1 }
  s.f = 300
  u64(s.f)
}
## expect: reject "type mismatch" "at line 11"
