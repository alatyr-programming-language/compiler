## e2e — 2-segment ALIAS injection: a single-file compile that binds `vec := alloc::vec` (a 2-seg
## module alias, NOT a 3-seg `alloc::vec::…` path) must still inject `lib/alloc/vec.al` so the
## alias-qualified `vec::with_capacity` / `vec::push` resolve. (A manifest/package build does NOT
## inject 2-seg aliases — the self-host `src/` has real such aliases; that gate keeps the fixpoint.)
## Push 10, 20, 12 into an arena-backed Vec via the alias, then sum: 10 + 20 + 12 = 42.
vec := alloc::vec
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut v := vec::with_capacity(u64, ptr(ar), 16)
  vec::push(u64, v, 10).expect("push")
  vec::push(u64, v, 20).expect("push")
  vec::push(u64, v, 12).expect("push")
  mut sum : u64 = 0
  unchecked {
    for x in v {
      sum = sum + x
    }
  }
  return sum
}
