## e2e / issue #1403 — `for x in …` over a `u8`/`i8` slice steps by one byte in every shape.
##
## Types §6.4 makes element `i` of a slice live at `base + i × stride`, the stride being the element's
## size; Control Flow §6 makes a slice iterable, yielding each element. The issue's rows, each its own
## check: the issue's own program (a call result straight in the loop header), the same at `i8`, a view
## local `v := t[1..4]`, a range in the loop header `for x in t[1..4]`, a `Slice(i8)` parameter, and an
## annotated `s : Slice(u8) = a[0..3]`. `test/issue1403_for_slice_bound_no_annotation.al` holds the
## bound call result and the `Vec` rows. Each check owns a code from 1 up; 42 means all held.
##
## NON-VACUOUS: at `e77d025e` (omen, native x86_64) the call-result rows answered 1, the view local
## SIGSEGV'd (139), the range header trapped (132), the `Slice(i8)` parameter answered 1, and at
## `cdcecb5c` the annotated row answered 0 where 123 is due. At `dc9e18e2` the default x86_64 path (the
## IR selector) answers 42.
pass := fn(s : Slice(u8)) -> Slice(u8) { s }
passi := fn(s : Slice(i8)) -> Slice(i8) { s }

gi := fn(s : Slice(i8)) -> i64 {
  mut n : i64 = 0
  for x in s { n = n * 31 + i64(x) }
  n
}

main := fn() -> u64 {
  t : [u8; 4] = [1, 200, 3, 255]
  mut n : i64 = 0
  for x in pass(t[0..4]) { n = n * 31 + i64(x) }
  if n != 1 * 29791 + 200 * 961 + 3 * 31 + 255 { return 1 }
  ti : [i8; 4] = [1, -2, 3, -128]
  mut m : i64 = 0
  for x in passi(ti[0..4]) { m = m * 31 + i64(x) }
  if m != 1 * 29791 + (-2) * 961 + 3 * 31 + (-128) { return 2 }
  mut nv : i64 = 0
  v := t[1..4]
  for x in v { nv = nv * 31 + i64(x) }
  if nv != 200 * 961 + 3 * 31 + 255 { return 3 }
  mut nh : i64 = 0
  for x in t[1..4] { nh = nh * 31 + i64(x) }
  if nh != 200 * 961 + 3 * 31 + 255 { return 4 }
  if gi(ti[0..4]) != 1 * 29791 + (-2) * 961 + 3 * 31 + (-128) { return 5 }
  a : [u8; 3] = [1, 2, 3]
  s : Slice(u8) = a[0..3]
  mut k : u64 = 0
  for x in s { k = k * 10 + u64(x) }
  if k != 123 { return 6 }
  42
}
## expect: run 42
