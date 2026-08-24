## e2e/fmt — the `@alloc(a) x := init` STORAGE ATTRIBUTE (D84 / Memory §2.4) survives a reformat.
## The parser desugars it into a plain `x := alloc_into(a, init)` (or the explicit-T
## `alloc_into(isize, a, init)` for a bare integer literal) and records the marker NOWHERE, so fmt
## re-emitted the desugar. Two things died with the marker: the surface form itself, and the
## base-allocator PRELUDE INJECTION that the bare `@alloc` drives — so the reformatted file no longer
## resolved `arena_over` / `alloc_into` / `get` at all and failed to build (`ambient_alloc_attr`,
## `ambient_alloc_scalar`, `ambient_alloc_deref_field`, `callfield_ptr_ret` all ran before a reformat
## and stopped building after it). There is no way to rebuild the surface form from the desugared
## call, so the statement is copied VERBATIM from the `@` to the end of its line.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

P := struct { x : u64, y : u64 }

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  @alloc(ar) h := P(x = 30, y = 2)
  @alloc(ar) n := 10
  s := deref(get(P, ar, h))
  m := get(isize, ar, n)
  return s.x + s.y + u64(deref(m))
}
