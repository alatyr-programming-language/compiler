## e2e — `alloc::with(A)` allocator-arg ELISION (MEM-5 / Grammar §130 `alloc-with-region`). Inside the
## scope, `with_capacity(u64, 16)` OMITS its `ptr(mut Arena)` allocator; the driver's elision pass
## splices `ptr(ar)` in at that parameter's position (the same code the explicit `ptr(ar)` form emits).
## Push 10, 20, 12 into the arena-backed Vec, then sum with a for-loop: 10 + 20 + 12 = 42.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut sum : u64 = 0
  alloc::with(ar) {
    mut v := alloc::vec::with_capacity(u64, 16)
    alloc::vec::push(u64, v, 10).expect("push")
    alloc::vec::push(u64, v, 20).expect("push")
    alloc::vec::push(u64, v, 12).expect("push")
    unchecked {
      for x in v {
        sum = sum + x
      }
    }
  }
  return sum
}
