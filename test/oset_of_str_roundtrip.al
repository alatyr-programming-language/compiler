## CLAYOUT S3(b) — an `OSet(str)` must keep, order and find its elements by VALUE.
##
## `alloc::oset` reaches an element through `oset_elem(T, s, i) -> ptr(mut T)`; every ordering
## decision reads one (`e := deref(oset_elem(…))` inside `oset_lower_bound` / `oset_contains`). At the
## use site the POINTEE type was not recoverable, so at `T = str` the binding took ONE scalar word and
## the comparison callback received a `str` whose length was the element's POINTER word. Measured
## before this stage on the shipped stdlib: the second insert handed `less` an `a.len` of
## 755049445839631474 and the program SEGFAULTED inside `str_cmp` — a wrong value that only crashed by
## luck (I11).
##
## The fix resolves the callee's returned pointee (`T`) by TYPE-PARAMETER POSITION through the call's
## type argument. Elements of THREE DIFFERENT lengths are inserted OUT OF ORDER, then probed for
## membership with exact values, with PREFIXES of stored values, and with a value sorting between two
## of them — so content, not a length, decides every answer. (`oset_as_slice` is deliberately NOT read
## here: a `Slice(str)` ELEMENT read is a separate, pre-existing defect — the element-stride sub-stage
## S3(c) — and this fixture must lock THIS fix, not encode that one.) Returns 42.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

slt := fn(a : str, b : str) -> bool {
  c := base::str::str_cmp(a, b)
  z : i64 = 0
  return c < z
}

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 262144, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 262144)

  mut s := alloc::oset::oset(str, ptr(ar), 8)
  alloc::oset::oset_insert(str, s, "wxyz", slt).expect("insert")
  alloc::oset::oset_insert(str, s, "abc", slt).expect("insert")
  alloc::oset::oset_insert(str, s, "hi", slt).expect("insert")
  if alloc::oset::oset_len(str, ptr(s)) != 3 { return 1 }

  ## a duplicate is a no-op (it must be FOUND by value, not by a garbage length)
  d := alloc::oset::oset_insert(str, s, "abc", slt).expect("dup")
  if d { return 2 }
  if alloc::oset::oset_len(str, ptr(s)) != 3 { return 3 }

  if not alloc::oset::oset_contains(str, ptr(s), "abc", slt) { return 4 }
  if not alloc::oset::oset_contains(str, ptr(s), "hi", slt) { return 5 }
  if not alloc::oset::oset_contains(str, ptr(s), "wxyz", slt) { return 6 }
  if alloc::oset::oset_contains(str, ptr(s), "zz", slt) { return 7 }
  if alloc::oset::oset_contains(str, ptr(s), "ab", slt) { return 8 }

  ## Every ordering decision (`oset_lower_bound`) reads elements through `deref(oset_elem(...))`, so
  ## a near-miss probe that is a PREFIX of a stored element, and one that would sort between two of
  ## them, can only answer correctly if the whole view — pointer AND length — came back.
  if alloc::oset::oset_contains(str, ptr(s), "abcd", slt) { return 9 }
  if alloc::oset::oset_contains(str, ptr(s), "h", slt) { return 10 }
  if alloc::oset::oset_contains(str, ptr(s), "wxy", slt) { return 11 }
  if alloc::oset::oset_contains(str, ptr(s), "", slt) { return 12 }

  ## a fourth element sorting BETWEEN two existing ones exercises the binary search over real
  ## contents, then must itself be found back
  alloc::oset::oset_insert(str, s, "b", slt).expect("insert b")
  if alloc::oset::oset_len(str, ptr(s)) != 4 { return 13 }
  if not alloc::oset::oset_contains(str, ptr(s), "b", slt) { return 14 }
  if not alloc::oset::oset_contains(str, ptr(s), "abc", slt) { return 15 }
  if not alloc::oset::oset_contains(str, ptr(s), "hi", slt) { return 16 }
  if not alloc::oset::oset_contains(str, ptr(s), "wxyz", slt) { return 17 }
  return 42
}
