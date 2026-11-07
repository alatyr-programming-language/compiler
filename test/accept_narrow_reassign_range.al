## e2e (#1283) - the CONTROL: every write the new representability check must LEAVE ALONE stays
## accepted and runs. In-range re-assignments at `u8`/`i8`/`i16` (including both bounds), in-range
## field stores, a re-assignment of a non-literal value, and the native-width forms the check does
## not judge. Measured on main `aab6ce1a` and after the fix: check rc 0, run rc 42 on x86_64.
S := struct { f : u8, g : i16 }

add100 := fn(v : u8) -> u8 { v }

main := fn() -> i64 {
  mut x : u8 = 1
  x = 200
  if u64(x) != 200 { return 1 }
  x = 255
  if u64(x) != 255 { return 2 }
  x = 0
  if u64(x) != 0 { return 3 }
  mut y : i8 = 0 - 128
  if i64(y) != 0 - 128 { return 4 }
  y = 127
  if i64(y) != 127 { return 5 }
  mut s := S(f = 1, g = 7)
  s.f = 255
  if u64(s.f) != 255 { return 6 }
  s.g = 0 - 32768
  if i64(s.g) != 0 - 32768 { return 7 }
  s.g = 32767
  if i64(s.g) != 32767 { return 8 }
  mut w : u64 = 18446744073709551615
  w = 0
  if w != 0 { return 9 }
  mut z : u8 = 1
  z = add100(7)
  if u64(z) != 7 { return 10 }
  42
}
## expect: run 42
