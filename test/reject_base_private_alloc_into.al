## Issue #524 — `alloc_into` (lib/base/alloc.al) stays PRIVATE, and this row is the proof that the
## marker unit did not publish it. Modules §3 line 73 defines visibility as who may *name* a
## declaration; nobody names `alloc_into` in source — the `@alloc(a) x := init` desugar synthesizes
## that callee span in `src/parser.al` — and the Stdlib appendix defines no `alloc_into` identifier.
## Publishing it would add a base-API name the specification does not define.
##
## Line 24 shows the specified spelling of the same operation: `@alloc(ar) h := 40` is accepted and
## its handle is read back through the published §5.2.1 `get`, so the arena surface is reachable.
## Line 26 names `alloc_into` explicitly and is refused. Red on the parent for a DIFFERENT line: the
## parent has no `pub arena_over`, so its rejection lands on line 23.
##
## ORDERING NOTE. This row locks only the QUALIFIED spelling. The UNQUALIFIED `alloc_into(u64, ar, 42)`
## from user source still resolves today through the visibility hole of #403 (the `pub` test is
## consulted only in the qualified arm of `sema.al`'s resolver). Closing that hole is #403's unit;
## `test/ambient_alloc_into.al` and `test/ambient_alloc_into_struct.al` carry the rows that flip from
## accept to reject when it lands.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := base::alloc::arena_over(bp, 65536)
  @alloc(ar) h := 40
  p := base::alloc::get(isize, ar, h)
  q := base::alloc::alloc_into(u64, ar, 42)
  return u64(deref(p)) + 2
}
