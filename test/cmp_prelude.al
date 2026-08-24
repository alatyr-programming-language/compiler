## e2e (base/cmp `min`/`max`/`clamp` usable from the PRELUDE). cmp + num are now prepended to the
## ambient prelude (with assert/result/option/alloc/slice). Their `lt`/`eq`/arithmetic OPERATORS are
## same-name-per-type overloads (all mangle to `cmp__lt` / `num__+` …), but the lean lower uses
## BUILT-IN operators so none is reached → dead-code elimination drops every unused overload before
## emission (no duplicate-label collision). The generic `min`/`max`/`clamp` emit per instantiated type.
## Here (after an alloc reference triggers the prelude): min(40,100)=40, max(2,1)=2 → 42.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut v := alloc::vec::new(u64, ptr(ar))
  alloc::vec::push(u64, v, 7).expect("p")
  lo := min(u64, 40, 100)
  hi := max(u64, 2, 1)
  lo + hi
}
