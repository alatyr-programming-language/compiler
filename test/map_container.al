## e2e (container-mono facet d — QUALIFIED-callee disambiguation): drives the allocator-borne
## `alloc::map` end to end over a raw `mmap` region. The load-bearing point is that
## `alloc::map::get(m, 7)` must resolve to `alloc::map`'s OWN NON-generic `get(m, key) -> Option(u64)`
## and NOT be conflated with `base/alloc`'s GENERIC `get(T, a, h)` (same tail name, different module).
## Two seams cooperate: `generic_decl_of` treats the qualified call as NON-generic (a same-tail
## non-generic decl exists in the resolved head module), and `emit_mangled_call`/`callee_decl_idx`
## compare the qualified head module (`alloc::map`) against the decl's MANGLED module (`alloc__map`)
## segment-aware (`::` ≡ `__`) so the label is `alloc__map__get`. `mmap` a page, `arena_over` it,
## build a map, insert (7 -> 42), read it back; a correct Some(42) exits 42 (a mis-resolution would
## not even link). Uses a raw `@abi(syscall)` mmap (no `std::os`) so the test is self-contained.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 4096, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 4096)
  m := map_new(ptr(ar), 16)
  insert(m, 7, 42)
  rr := alloc::map::get(m, 7)
  match rr {
    Option::Some(v) => { u64(v) }
    Option::None => { 1 }
  }
}
