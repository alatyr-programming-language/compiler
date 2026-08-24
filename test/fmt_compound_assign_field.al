## e2e fmt focused regression (Tooling §4.2; Grammar §130; OP-2): canonical formatting retains
## the authored compound-assignment surface for a field place. The parser lowers these statements
## to ordinary field stores with binary right-hand sides, so this exercises source-span recovery at
## the field name while checking canonical idempotence and runtime preservation.
##
## Expected exit: 42. Each of the eight operator families updates the same field and is checked
## before the next one, so a formatted program cannot hide a changed operation behind the final value.
Acc := struct { v : u64 }

main := fn() -> u64 {
  mut a := Acc(v = 100)
  a.v += 7
  if a.v != 107 { return 1 }
  mut b := Acc(v = 100)
  b.v -= 7
  if b.v != 93 { return 2 }
  mut c := Acc(v = 100)
  c.v *= 7
  if c.v != 700 { return 3 }
  mut d := Acc(v = 100)
  d.v /= 7
  if d.v != 14 { return 4 }
  mut e := Acc(v = 100)
  e.v %= 7
  if e.v != 2 { return 5 }
  mut f := Acc(v = 100)
  f.v &= 7
  if f.v != 4 { return 6 }
  mut g := Acc(v = 100)
  g.v |= 7
  if g.v != 103 { return 7 }
  mut h := Acc(v = 100)
  h.v ^= 7
  if h.v != 99 { return 8 }
  return 42
}
