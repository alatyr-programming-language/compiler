## Issue #429 — the fence added for a `str` element write must not touch a place that the
## specification DOES make writable. Every legitimate store form named by the issue is exercised
## once, and each one reports its own failure code (>= 100) so a broken step names itself instead
## of disappearing into a sum: no total is formed, and no two steps can trade errors.
##
## Memory §3.3's AND rule is what separates these from `s[0] = 65`: a `mut` local array element,
## a `mut` field, and `deref(p)` where `p : ptr(mut u64)` each have a writable step at every
## position of the path. The `str` READ beside them (`bytes(t)[1]`) is a load, never a store, and
## also has to survive.
##
## Expected exit: 57 on x86_64. The non-x86 backends may trap on a construct they do not
## implement; what they may not do is run to a different value below 128.
S := struct { mut v : u64, w : u64 }

main := fn() -> u64 {
  mut a : [u64; 3] = [4, 9, 2]
  a[0] = 41
  if a[0] != 41 { return 101 }
  if a[1] != 9 { return 102 }
  if a[2] != 2 { return 103 }
  mut s := S(v = 5, w = 6)
  s.v = 17
  if s.v != 17 { return 104 }
  if s.w != 6 { return 105 }
  mut w : u64 = 3
  p := ptr(mut w)
  deref(p) = 23
  if w != 23 { return 106 }
  t := "abc"
  if bytes(t)[1] != 98 { return 107 }
  if bytes(t)[0] != 97 { return 108 }
  57
}
