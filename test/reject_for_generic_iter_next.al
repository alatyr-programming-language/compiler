## e2e (reject) — Stdlib appendix §2.4: `alloc::hashmap::HashMapIter` provides `next`, so it is an
## ITERATOR and the built-in counted loop is the wrong form for it. Its `next` is declared
## `next(K : type, V : type, in out it : HashMapIter(K, V))`, and the shared `for`-form desugar
## builds an unqualified one-argument call, so this loop cannot be driven from `for` yet.
##
## The point of the fixture is that it must not COMPILE INTO the counted loop. Failure-first on
## parent f14b3d9 (x86_64, default build path): this program built rc 0 and ran to `100` — the loop
## body never executed for a map holding two live entries, a silent wrong value with no diagnostic at
## all. Here the build is refused and says why, and the explicit driver stays available.
##
## The searched text is deliberately absent from this header (the `*_has` helpers grep the whole
## artifact).

sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut m := alloc::hashmap::new(u64, u64, ptr(ar))
  alloc::hashmap::hashmap_insert(u64, u64, ptr(m), ar, 7, 42).expect("insert")
  alloc::hashmap::hashmap_insert(u64, u64, ptr(m), ar, 8, 43).expect("insert")
  mut it := alloc::hashmap::hashmap_iter(u64, u64, ptr(m), ar)
  mut k : u64 = 0
  for e in it {
    k = k + 1
    if k > 30 { return 99 }
  }
  100 + k
}
