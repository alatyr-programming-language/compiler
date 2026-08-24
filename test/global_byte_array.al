## BYTES — x86 module-global byte arrays. Explicit [u8|i8|bits8; N] globals use one-byte
## `.data` cells, byte-stride indexed reads, checked bounds, ptr(element), and mutable writes.
mut UG : [u8; 4] = [10, 20, 30, 40]
IG : [i8; 3] = [-1, 2, 3]
BG : [bits8; 2] = [5, 6]

main := fn() -> u64 {
  p0 := unchecked bitcast(usize, ptr(UG[0]))
  p1 := unchecked bitcast(usize, ptr(UG[1]))
  p3 := unchecked bitcast(usize, ptr(UG[3]))
  c0 := unchecked bitcast(usize, ptr(IG[0]))
  c1 := unchecked bitcast(usize, ptr(IG[1]))
  UG[1] = 42
  mut ok := p1 - p0 == 1 and p3 - p0 == 3 and c1 - c0 == 1
  ok = ok and UG[0] == 10 and UG[1] == 42 and UG[3] == 40
  ok = ok and IG[0] < 0 and IG[1] == 2 and BG[1] == 6
  if ok { 42 } else { 1 }
}
