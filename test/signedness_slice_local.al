## P1 signedness: a typed Slice(u64) LOCAL must retain its declared element type
## through a range-view binding. Before the bounded fix, xs[0] < xs[1] fell
## back to signed setl at the high-bit boundary; the control remains signed.
main := fn() -> u64 {
  arr : [u64; 2] = [0, 18446744073709551615]
  xs : Slice(u64) = arr[0..2]
  if xs[0] < xs[1] { return 42 }
  return 1
}
