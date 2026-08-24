## e2e — alloc::oset ordered set: insert keeps the backing sorted + duplicate-free via a caller `less`
## comparator (binary search + tail shift, growth from cap 2). Insert 30,10,20,10(dup),5 → the sorted
## slice is [5,10,20,30], the duplicate is rejected, and contains reflects membership. Returns 42 iff all
## exact.
os := alloc::oset
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

lt := fn(a : u64, b : u64) -> bool { a < b }

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut s := os::oset(u64, ptr(ar), 2)

  os::oset_insert(u64, s, 30, lt).expect("i")
  os::oset_insert(u64, s, 10, lt).expect("i")
  os::oset_insert(u64, s, 20, lt).expect("i")
  dup := os::oset_insert(u64, s, 10, lt).expect("i")   ## duplicate -> false
  if dup { return 1 }
  os::oset_insert(u64, s, 5, lt).expect("i")

  if os::oset_len(u64, ptr(s)) != 4 { return 2 }
  if not os::oset_contains(u64, ptr(s), 20, lt) { return 3 }
  if os::oset_contains(u64, ptr(s), 99, lt) { return 4 }
  if os::oset_contains(u64, ptr(s), 5, lt) == false { return 5 }

  sl := os::oset_as_slice(u64, ptr(s))
  if sl[0] != 5 { return 6 }
  if sl[1] != 10 { return 7 }
  if sl[2] != 20 { return 8 }
  if sl[3] != 30 { return 9 }
  return 42
}
