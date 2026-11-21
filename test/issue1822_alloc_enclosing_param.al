## Functions §5.5 step (2): within a function body its own allocator parameter IS the ambient, so the
## call `take(41)` inside `outer` binds `take`'s `ar` to `outer`'s `ar`, and 41 to `x`. Not implemented
## yet (#1468): the call-binding check (#1822) refuses it at check, located and naming `ar`, instead of
## a build that reads `ar` and `x` from stray registers. 41 + 1 = 42 once #1468 lands.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
take := fn(ar : ptr(mut Arena), x : u64) -> u64 { x + 1 }
outer := fn(ar : ptr(mut Arena)) -> u64 { take(41) }
main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(std::sysno::MMAP, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  outer(ptr(ar))
}
## expect: run 42
