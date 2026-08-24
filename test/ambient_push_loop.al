## e2e — the arraysum-core pattern: a UFCS `v.push(i)` where BOTH the receiver `v` and the arg `i` are
## locals declared INSIDE an `alloc::with(A) { … }` block, followed by `for x in v`. This was blocked —
## the mono pre-pass couldn't resolve `push`'s type argument (`i` is nested in the alloc::with body, not a
## fn-flat local), so `alloc__vec__push__u64` was referenced but never collected (undefined at link). Fixed
## by pointing COLLECT_BODY at the alloc::with body during the descent. Push 0,1,2 (sum 3) then + 39 = 42.
## Raw `@abi(syscall)` mmap arena so the test is self-contained (no std::os).
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
vec := alloc::vec

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut sum : u64 = 39
  alloc::with(ar) {
    mut v := vec::with_capacity(u64, usize(8))
    mut i : u64 = 0
    unchecked {
      while i < 3 {
        p := v.push(i)
        i += 1
      }
    }
    unchecked {
      for x in v {
        sum += x
      }
    }
  }
  return sum
}
