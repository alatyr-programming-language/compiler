## e2e (arr[lo..hi] slicing a [str; N] LOCAL builds a correct Slice(str)). Range-slicing a local
## array of str previously mis-built the view (it took the str-BYTE-view path, reading the 2-word str
## elements as a flat byte buffer). Now it builds a typed Slice(str) (ek 5, stride 2, eek 4): s.len,
## s[i] element {ptr,len} reads, and `for x in s` iteration all read the right str elements. Returns 42.
main := fn() -> u64 {
  arr := ["ab", "cde", "fghi"]
  s := arr[0..2]
  mut r : u64 = 0
  if s.len() == 2 { r = r + 1 }              ## slice length
  if str_eq(s[0], "ab") { r = r + 2 }        ## element 0 {ptr,len}
  if str_eq(s[1], "cde") { r = r + 4 }       ## element 1 {ptr,len}
  mut sum : u64 = 0
  for x in s { sum = sum + x.len() }
  if sum == 5 { r = r + 8 }                  ## for-loop len iteration (2 + 3)
  mut lc : u64 = 0
  for x in s {
    if str_eq(x, "ab") { lc = lc + 1 }
    if str_eq(x, "cde") { lc = lc + 2 }
  }
  if lc == 3 { r = r + 16 }                  ## for-loop CONTENT (ptr correctness)
  s2 := arr[1..3]
  if str_eq(s2[0], "cde") { r = r + 11 }     ## non-zero `lo` base-pointer offset
  r
}
