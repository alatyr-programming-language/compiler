## #1181 — `t[i] = <view>` into a `[Slice(u8); N]` element stores the whole two-word {ptr, len} pair
## (Types §7: a view "array element holds the two-word pair itself"), from a range slice and from a
## view local. Expected exit 42; a failing check exits its own number. NON-VACUOUS: the parent refused
## the store.
main := fn() -> u64 {
  a : [u8; 3] = [1, 2, 3]
  b : [u8; 2] = [4, 5]
  mut t : [Slice(u8); 2] = [a[0..3], b[0..2]]
  t[1] = a[0..1]
  if u64(t[1].len) * 10 + u64(t[0].len) != 13 { return 1 }
  x := b[1..2]
  t[0] = x
  if t[0].len != 1 { return 2 }
  if t[0][0] != 5 { return 3 }
  42
}
## expect: run 42
