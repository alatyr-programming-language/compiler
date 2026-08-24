## CLAYOUT S3(b) — an `OMap(u64, str)` must round-trip its VALUES.
##
## `alloc::omap` reaches a value through `omap_val_elem(K, V, m, i) -> ptr(mut V)`. At the use site the
## POINTEE type was not recoverable, so the two-word §7 `{ptr, len}` view was never materialized even
## though `omap_get` already binds the value to a LOCAL first (`v := deref(omap_val_elem(…))`) — the
## binding took ONE scalar word. Measured before this stage on the shipped stdlib with 7 -> "abc" and
## 9 -> "wxyz": both lookups returned `Some` with `len` = 192, and `str_eq(v, "abc")` false. Silent
## wrong values (I11).
##
## The fix resolves the callee's returned pointee (`V`) by TYPE-PARAMETER POSITION through the call's
## type argument. This checks CONTENT with values of DIFFERENT lengths, and also reads back through
## `omap_values` (the `Slice(V)` surface) so the element stride and the view agree. Returns 42.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

ult := fn(a : u64, b : u64) -> bool { a < b }

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 262144, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 262144)

  mut m := alloc::omap::omap(u64, str, ptr(ar), 8)
  alloc::omap::omap_insert(u64, str, m, 9, "wxyz", ult).expect("insert")
  alloc::omap::omap_insert(u64, str, m, 7, "abc", ult).expect("insert")
  alloc::omap::omap_insert(u64, str, m, 11, "hi", ult).expect("insert")
  if alloc::omap::omap_len(u64, str, ptr(m)) != 3 { return 1 }

  g7 := alloc::omap::omap_get(u64, str, ptr(m), 7, ult)
  match g7 {
    Option::Some(t) => {
      if t.len != 3 { return 2 }
      if not str_eq(t, "abc") { return 3 }
    }
    Option::None => { return 4 }
  }
  g9 := alloc::omap::omap_get(u64, str, ptr(m), 9, ult)
  match g9 {
    Option::Some(t) => {
      if t.len != 4 { return 5 }
      if not str_eq(t, "wxyz") { return 6 }
      b := bytes(t)
      if u64(b[0]) != 119 { return 7 }
      if u64(b[3]) != 122 { return 8 }
    }
    Option::None => { return 9 }
  }
  g11 := alloc::omap::omap_get(u64, str, ptr(m), 11, ult)
  match g11 {
    Option::Some(t) => {
      if t.len != 2 { return 10 }
      if not str_eq(t, "hi") { return 11 }
    }
    Option::None => { return 12 }
  }
  gx := alloc::omap::omap_get(u64, str, ptr(m), 8, ult)
  match gx {
    Option::Some(t) => { return 13 }
    Option::None => {}
  }
  if not alloc::omap::omap_contains(u64, str, ptr(m), 11, ult) { return 14 }

  ## a duplicate key OVERWRITES its value — the replacement must come back whole
  alloc::omap::omap_insert(u64, str, m, 7, "abcdef", ult).expect("reinsert")
  if alloc::omap::omap_len(u64, str, ptr(m)) != 3 { return 15 }
  g7b := alloc::omap::omap_get(u64, str, ptr(m), 7, ult)
  match g7b {
    Option::Some(t) => {
      if t.len != 6 { return 16 }
      if not str_eq(t, "abcdef") { return 17 }
    }
    Option::None => { return 18 }
  }
  return 42
}
