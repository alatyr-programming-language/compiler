## Issue #788 / Control Flow §5.1/§5.4 — the OVER-REJECTION control: every scrutinee shape the widened
## check now decides, written EXHAUSTIVELY, must stay accepted and run. Complete array-element matches
## over a local and a parameter (statement and value position), `bool` covered by `true` + `false`
## (and by an OR-pattern), integer literals with a `_` default, and ranges covering the whole width of
## `u8`, `i8` and `u16`. The parts add up to the fixture convention's 42.
C := enum { R, G, B }
elem := fn(xs : [C; 3], i : usize) -> u64 {
  match xs[2] { R => { return 1 }; G => { return 2 }; B => { return 3 } }
  return 0
}
flag := fn(b : bool) -> u64 {
  r := match b { true => { 2 }; false => { 1 } }
  return r
}
main := fn() -> u64 {
  mut total : u64 = 0
  xs : [C; 3] = [C.R, C.G, C.B]
  match xs[1] { R => { total += 1 }; G => { total += 2 }; B => { total += 3 } }
  v : u64 = match xs[2] { R => { 1 }; G => { 2 }; B => { 3 } }
  total += v
  total += elem(xs, 0)
  b := false
  match b { true => { total += 1 }; false => { total += 2 } }
  total += flag(true) + flag(false)
  match b { true | false => { total += 1 } }
  n : u8 = 7
  match n { 0 => { total += 100 }; 1 => { total += 100 }; _ => { total += 5 } }
  w : u64 = match n { 0..=6 => { 100 }; 7..=255 => { 6 } }
  total += w
  k : i8 = -3
  match k { -128..=-1 => { total += 4 }; 0..=127 => { total += 100 } }
  m : u16 = 300
  match m { 0..256 => { total += 100 }; 256..=65535 => { total += 7 } }
  big : u64 = 9
  match big { 9 => { total += 6 }; _ => { total += 100 } }
  return total
}
