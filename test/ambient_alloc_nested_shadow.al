## e2e — MEM-5 nested ambient allocator shadowing and restoration.
## `alloc::vec::with_capacity` has the elidable `ptr(mut Arena)` parameter:
## omitted calls must follow the current alloc::with arena, while an explicit
## `ptr(outer)` remains in control even inside the nested inner scope.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  b1 := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  b2 := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  p1 := unchecked bitcast(ptr(mut bits8), bitcast(usize, b1))
  p2 := unchecked bitcast(ptr(mut bits8), bitcast(usize, b2))
  mut outer := arena_over(p1, 65536)
  mut inner := arena_over(p2, 65536)

  alloc::with(outer) {
    first := alloc::vec::with_capacity(u64, 1)
    alloc::with(inner) {
      nested := alloc::vec::with_capacity(u64, 1)
      explicit := alloc::vec::with_capacity(u64, ptr(outer), 1)
      if first.cap != 1 { return 1 }
      if nested.cap != 1 { return 2 }
      if explicit.cap != 1 { return 3 }
      if inner.off != 8 { return 4 }
      if outer.off != 16 { return 5 }
    }
    restored := alloc::vec::with_capacity(u64, 1)
    if restored.cap != 1 { return 6 }
    if outer.off != 24 { return 7 }
  }
  if outer.off != 24 { return 8 }
  if inner.off != 8 { return 9 }
  return 42
}
