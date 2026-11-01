## #1181 — a byte-slice view LOCAL (`x := a[0..3]`) stored into a `Slice(u8)` struct field carries its
## own {ptr, len}. Expected exit 33: `s.v.len` = 3, `s.v[2]` = 3. The parent read the view as a fixed
## array parameter, stored a zero length, and trapped on the bounds check.
S := struct { v : Slice(u8) }

main := fn() -> u64 {
  a : [u8; 3] = [1, 2, 3]
  x := a[0..3]
  s := S(v = x)
  u64(s.v.len) * 10 + u64(s.v[2])
}
