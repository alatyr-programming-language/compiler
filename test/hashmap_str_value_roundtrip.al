## P1-CLAYOUT S3(b) — a `HashMap(u64, str)` must round-trip its VALUES.
##
## `alloc::hashmap` reaches a value through `val_at(K, V, m, a, i) -> ptr(mut V)`. At the use site the
## POINTEE type was not recoverable, so the two-word §7 `{ptr, len}` view was never materialized:
## `v := deref(val_at(…))` bound ONE scalar word. Measured before this stage on the shipped stdlib
## with 7 -> "abc" and 9 -> "wxyz": `get(m, 7)` returned `Some` with `len` = 7 and `get(m, 9)` `len`
## = 9 — the KEY leaking into the length word, and `str_eq(v, "abc")` false. Silent wrong values (I11).
##
## The fix resolves the callee's returned pointee (`V`) by TYPE-PARAMETER POSITION through the call's
## type argument. This checks CONTENT with values of DIFFERENT lengths so a shared length cannot pass
## by accident, and exercises `get`, `contains` and an overwriting re-`insert`. Returns 42.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 262144, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 262144)

  mut m := alloc::hashmap::with_capacity(u64, str, ptr(ar), 16)
  alloc::hashmap::insert(u64, str, ptr(m), ar, 7, "abc").expect("insert")
  alloc::hashmap::insert(u64, str, ptr(m), ar, 9, "wxyz").expect("insert")
  alloc::hashmap::insert(u64, str, ptr(m), ar, 11, "hi").expect("insert")
  if alloc::hashmap::len(u64, str, ptr(m), ar) != 3 { return 1 }

  g7 := alloc::hashmap::get(u64, str, ptr(m), ar, 7)
  match g7 {
    Option::Some(t) => {
      if t.len != 3 { return 2 }
      if not str_eq(t, "abc") { return 3 }
    }
    Option::None => { return 4 }
  }
  g9 := alloc::hashmap::get(u64, str, ptr(m), ar, 9)
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
  g11 := alloc::hashmap::get(u64, str, ptr(m), ar, 11)
  match g11 {
    Option::Some(t) => {
      if t.len != 2 { return 10 }
      if not str_eq(t, "hi") { return 11 }
    }
    Option::None => { return 12 }
  }
  gx := alloc::hashmap::get(u64, str, ptr(m), ar, 13)
  match gx {
    Option::Some(t) => { return 13 }
    Option::None => {}
  }
  if not alloc::hashmap::contains(u64, str, ptr(m), ar, 7) { return 14 }

  ## overwrite an existing key: the new (longer) value must come back whole
  alloc::hashmap::insert(u64, str, ptr(m), ar, 7, "abcdef").expect("reinsert")
  g7b := alloc::hashmap::get(u64, str, ptr(m), ar, 7)
  match g7b {
    Option::Some(t) => {
      if t.len != 6 { return 15 }
      if not str_eq(t, "abcdef") { return 16 }
    }
    Option::None => { return 17 }
  }
  return 42
}
