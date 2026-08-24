## e2e — `alloc_into` (the trapping allocation backing `@alloc(a) x := init`) end to end
## through the AMBIENT allocator surface, for a SCALAR value. A raw `mmap` arena is wrapped by
## `arena_over`; the `alloc::strbuf::…` reference transitively injects the base `alloc` module so
## the bare `arena_over`/`alloc_into`/`get` resolve. `alloc_into(u64, ar, 42)` allocates a `u64`,
## writes it, and returns its `Handle`; `get` exchanges the handle for a scoped pointer whose
## deref recovers the stored 42. Guards the value-model store `deref(p) = init` and the by-ref
## handle bridge inside `alloc_into` (an explicit `Handle(T)` literal so `get` receives it by
## reference — see lib/base/alloc.al). Self-contained (no `std::os`), like `ambient_strbuf`.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  ## trigger base/alloc injection transitively via the alloc::strbuf lib module:
  mut sb := alloc::strbuf::strbuf(ptr(ar), 16)
  h := alloc_into(u64, ar, 42)
  p := get(u64, ar, h)
  return deref(p)
}
