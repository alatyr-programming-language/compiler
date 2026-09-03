## e2e (issue #394 — a SILENT WRONG VALUE). The BYTE at index `j` of the `str` ELEMENT `k` of a
## `[str; N]` local: `arr[k][j]`. Types §7 makes each element a two-word `{ptr, len}` view and
## appendix 160 §3.5 makes `str` a `[u8]`, so the read must resolve element `k`'s pair with the
## 2-word element stride and then load ONE byte at `ptr + j`.
##
## FAILURE-FIRST (measured on the parent, f5934b8): the base `Index(arr, k)` is not a `Var`, so
## every typed arm of the x86_64 `Expr::Index` read declined it and the untyped `emit_index_addr`
## tail resolved the unnamed base to frame SLOT 0, emitting `leaq -8(%rbp)` + `j*8` — a word of the
## frame prologue. The result did not depend on the array, on `k`, or on the string bytes:
## `arr[0][j]` and `arr[1][j]` were byte-identical, and `["ABCDEF", "uvwxyz"]` and `["zzzzzz", …]`
## produced the same values 0/0/5/1/180/0 for `j = 0..5`. The parent runs this fixture to 100 (the
## very first check, `arr[0][0]` == 65, read 0). The other three backends TRAP on this shape (133 /
## 133 / 134) before and after the fix, so no backend is turned from a trap into a wrong value.
##
## Failure codes start at 100 and every element is checked SEPARATELY: no `good * K + bad` aliasing
## and no commutative sum can hide one wrong byte behind another (issue #386). Neighbouring bytes
## are non-zero, distinct within an element, and disjoint between elements, so an ignored outer
## index cannot pass by luck.
main := fn() -> u64 {
  arr : [str; 3] = ["ABCDEF", "uvwxyz", "012345"]

  ## element 0 — first and last byte of the view
  if u64(arr[0][0]) != 65 { return 100 }    ## 'A'
  if u64(arr[0][5]) != 70 { return 101 }    ## 'F'

  ## element 1 — a DIFFERENT element must give DIFFERENT bytes at the SAME inner index
  if u64(arr[1][0]) != 117 { return 102 }   ## 'u'
  if u64(arr[1][5]) != 122 { return 103 }   ## 'z'

  ## element 2 — a third, disjoint byte range
  if u64(arr[2][2]) != 50 { return 104 }    ## '2'
  if u64(arr[2][0]) != 48 { return 105 }    ## '0'

  ## a NON-CONSTANT outer index and a non-constant inner index
  mut k : u64 = 1
  mut j : u64 = 3
  if u64(arr[k][j]) != 120 { return 106 }   ## "uvwxyz"[3] = 'x'
  k = 2
  j = 5
  if u64(arr[k][j]) != 53 { return 107 }    ## "012345"[5] = '5'

  ## the same read through a typed `Slice(str)` VIEW over the same array
  s := arr[0..3]
  if u64(s[2][4]) != 52 { return 108 }      ## "012345"[4] = '4'
  if u64(s[0][1]) != 66 { return 109 }      ## "ABCDEF"[1] = 'B'

  42
}
