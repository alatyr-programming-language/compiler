## P1 signedness: a typed Slice(u64) LOCAL must retain its declared element type
## through a range-view binding. Before the bounded fix, xs[0] < xs[1] fell
## back to signed setl at the high-bit boundary; the control remains signed.
##
## The signed control is the second half and is what makes this fixture able to
## FAIL an over-broad fix: `ss[0] < ss[1]` is -1 < 0, TRUE under signed ordering
## and FALSE under unsigned, so a change that made every indexed element unsigned
## would answer 1 here instead of 42. The header claimed this control before the
## body carried it (#707).
main := fn() -> u64 {
  arr : [u64; 2] = [0, 18446744073709551615]
  xs : Slice(u64) = arr[0..2]

  sarr : [i64; 2] = [0 - 1, 0]
  ss : Slice(i64) = sarr[0..2]

  if xs[0] < xs[1] {
    if ss[0] < ss[1] { return 42 }
  }
  return 1
}
