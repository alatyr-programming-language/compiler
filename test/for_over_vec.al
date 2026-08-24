## e2e — `for x in v` over an arena-backed `Vec(T)` (the iterator resolves the element base as
## `arena.base + idx`; a Vec's word 0 is the arena HANDLE index, not a pointer, so the plain slice
## path would deref a raw index and trap). Push 10, 20, 12 into a Vec over a raw mmap arena, then
## sum them with a for-loop: 10 + 20 + 12 = 42. Uses qualified `alloc::vec::…` (triggers injection).
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut v := alloc::vec::with_capacity(u64, ptr(ar), 16)
  alloc::vec::push(u64, v, 10).expect("push")
  alloc::vec::push(u64, v, 20).expect("push")
  alloc::vec::push(u64, v, 12).expect("push")
  mut sum : u64 = 0
  unchecked {
    for x in v {
      sum = sum + x
    }
  }
  return sum
}
