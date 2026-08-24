## e2e (flagship: the generic allocator-borne `alloc::vec` running AMBIENTLY, end to end). Over a raw
## `mmap` region + `arena_over`, `new(u64)` builds a `Vec(u64)`, `push` appends 42, `at(0)` reads it
## back — exercising the whole generic-container path: generic monomorphization, `allocate(…).expect(…)
## .idx` (the allocator actually runs — inline `?`/`.expect()` unwrap, `size`/`align` fold), the
## `Handle` returned + `get`-based element addressing, `deref(deref(v).arena)` (a struct field reached
## THROUGH a `ptr(Vec(T))` param then deref'd), and the in-out `Vec(T)` mutation. Exits 42.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 4096, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 4096)
  mut v := alloc::vec::new(u64, ptr(ar))
  pr := alloc::vec::push(u64, v, 42)
  alloc::vec::at(u64, ptr(v), 0)
}
