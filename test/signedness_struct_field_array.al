## P1 signedness: an indexed declared builtin-integer array field must retain
## its element type through the struct-field base.
Rec := struct { u : [u64; 2] }

main := fn() -> u64 {
  r : Rec = Rec(u = [0, 18446744073709551615])
  if r.u[0] < r.u[1] { return 42 }
  return 1
}
