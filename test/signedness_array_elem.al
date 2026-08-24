## e2e (I11 / signedness): native-width fixed-array elements carry a resolved integer type,
## but the lower type scan used to discard that type deliberately. Two indexed `[u64; N]`
## operands therefore fell through to the signed comparison default: `0 < u64::MAX`
## silently answered false because the high-bit element was read as `-1`.
##
## The signed array is a control: resolving an indexed `[i64; N]` element must keep the
## signed comparison path. Both operands are above the old 0/0 scan seam; success is 42.
main := fn() -> u64 {
  us : [u64; 2] = [0, 18446744073709551615]
  ss : [i64; 2] = [0 - 1, 0]

  if us[0] < us[1] {
    if ss[0] < ss[1] { return 42 }
  }
  return 1
}
