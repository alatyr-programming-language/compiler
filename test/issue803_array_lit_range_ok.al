## Issue #803 — the OVER-REJECTION control: array-literal elements AT the bounds of their element
## type stay accepted — `[0, 255]` for `[u8; 2]`, `[-128, 127]` for `[i8; 2]`, `[0, 65535]` for
## `[u16; 2]`, and an in-range literal argument to a `[u16; 3]` parameter. It runs to 42.
f := fn(xs : [u16; 3]) -> u64 { return u64(xs[0]) + u64(xs[1]) + u64(xs[2]) }
main := fn() -> u64 {
  a : [u8; 2] = [0, 255]
  b : [i8; 2] = [-128, 127]
  c : [u16; 2] = [0, 65535]
  mut total : u64 = u64(a[1]) - 255 + f([40, 1, 1])
  if b[0] < 0 and b[1] == 127 and c[1] == 65535 { total += 0 } else { total += 100 }
  return total
}
