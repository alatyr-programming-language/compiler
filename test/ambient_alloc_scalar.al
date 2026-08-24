## e2e — `@alloc(a) x := <int literal>` (D84): scalar-literal init. A bare integer literal has no
## inferable type, so the desugar passes an EXPLICIT `isize` (spec §3.4: a literal with no context
## takes the target's native signed integer) — `x := alloc_into(isize, ar, 42)`. `x : Handle(isize)`;
## `get(isize, ar, x)` recovers the stored 42. Standalone: the bare `@alloc` injects the base prelude.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  @alloc(ar) x := 42
  p := get(isize, ar, x)
  return u64(deref(p))
}
