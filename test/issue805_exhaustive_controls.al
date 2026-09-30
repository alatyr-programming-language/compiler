## Issue #805 / Control Flow §5.1/§5.4 — the OVER-REJECTION control: each shape the widened check now
## decides, written exhaustively, stays accepted and runs: `char` with a `_`, a complete match over a
## struct field array element, and ranges covering the whole of `i64`. The parts add 8 + 3 + 13 =
## 24; the constant lifts it to the fixture convention's 42.
C := enum { R, G, B }
H := struct { arr : [C; 2] }
ch := fn(c : char) -> u64 {
  r := match c { 'a' => { 1 }; _ => { 2 } }
  return r
}
signed := fn(n : i64) -> u64 {
  r := match n { -9223372036854775808..=-1 => { 6 }; 0..=9223372036854775807 => { 7 } }
  return r
}
main := fn() -> u64 {
  h := H(arr = [C.B, C.G])
  mut total : u64 = 18
  match h.arr[1] { R => { total += 100 }; G => { total += 8 }; B => { total += 100 } }
  total += ch('a') + ch('q')
  total += signed(-5) + signed(5)
  return total
}
