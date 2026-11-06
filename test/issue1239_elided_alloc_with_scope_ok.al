## e2e / issue #1239 — CONTROL: the fence must not refuse elision that DOES resolve.
##
## Issue #1239's fix refuses an elided allocator only when Functions §5.5 finds no ambient at all.
## Both legitimate forms stay expressible and must still build and run, or the fence has become a
## refusal of elision itself:
##   * explicit allocator — `with_capacity(u64, ptr(ar), 8)` names the arena, so §5.5 is not asked;
##   * `alloc::with(ar) { … }` — §5.5 step (1), the nearest enclosing scope, which the elision pass
##     splices `ptr(ar)` in for exactly as it did before.
## The explicit Vec contributes 0 so the sum is 10 + 20 + 12 = 42 either way.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(std::sysno::MMAP, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut sum : u64 = 0
  mut e := alloc::vec::with_capacity(u64, ptr(ar), 8)
  alloc::vec::push(u64, e, 0).expect("push")
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
## expect: run 42
