## e2e — S3(c): a `Slice(str)` returned by `oset_as_slice` must preserve the
## two-word `{ptr,len}` element when `sl[0]` is bound as a value. The direct
## `Slice(str)` PARAM path is a separate control; this exercises the returned
## Slice value's local slot metadata and the generic oset call shape.
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

  mut s := alloc::oset::oset(str, ptr(ar), 4)
  alloc::oset::oset_insert(str, s, "wxyz", slt).expect("insert")
  alloc::oset::oset_insert(str, s, "abc", slt).expect("insert")
  sl := alloc::oset::oset_as_slice(str, ptr(s))
  e0 := sl[0]
  e1 := sl[1]
  b0 := bytes(e0)
  b1 := bytes(e1)
  if e0.len != 3 { return 1 }
  if b0[0] != 97 { return 2 }
  if e1.len != 4 { return 3 }
  if b1[0] != 119 { return 4 }
  if not str_eq(sl[0], "abc") { return 5 }
  if not str_eq(sl[1], "wxyz") { return 6 }
  return 42
}
