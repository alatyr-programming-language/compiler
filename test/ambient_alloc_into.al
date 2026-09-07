## e2e — the ambient allocator surface for a SCALAR value, in BOTH spellings, end to end. A raw
## `mmap` arena is wrapped by `arena_over`; the `alloc::strbuf::…` reference transitively injects the
## base `alloc` module (this file's distinguishing injection route — `ambient_alloc_scalar` and
## `ambient_alloc_attr` cover the standalone `@alloc`-forced route instead). `get` exchanges a handle
## for a scoped pointer whose deref recovers the stored value. Guards the value-model store
## `deref(p) = init` and the by-ref handle bridge inside `alloc_into` (an explicit `Handle(T)` literal
## so `get` receives it by reference — see lib/base/alloc.al). Self-contained (no `std::os`).
##
## SPELLING 1 (line 33) — `@alloc(ar) hs := 40`, the language surface Memory §2.4 specifies. The
## parser desugars it to `alloc_into(isize, ar, 40)` through a SYNTHESIZED callee span, so no user
## source names `alloc_into`. Issue #524 keeps `alloc_into` private on exactly that ground: Modules
## §3 line 73 scopes visibility to who may *name* a declaration, and the Stdlib appendix defines no
## `alloc_into` identifier.
##
## SPELLING 2 (line 35) — the BARE `alloc_into(u64, ar, 2)` call from USER source. This is an instance
## of the #403 visibility hole living inside our own corpus: the `pub` test is consulted only in the
## qualified arm of `sema.al`'s resolver, so an unqualified reference to a private base declaration
## still resolves. It is kept here DELIBERATELY, not by oversight: it is the row that flips from
## accept to reject when #403 lands, at which point this file becomes a reject fixture on the bare
## call and its accept half is already covered by `ambient_alloc_scalar`. Do not "simplify" it away —
## `test/reject_base_private_alloc_into.al` locks the qualified spelling, which is refused today.
##
## 42 = 40 (the `@alloc` handle) + 2 (the bare-call handle). Either store failing misses 42.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  ## trigger base/alloc injection transitively via the alloc::strbuf lib module:
  mut sb := alloc::strbuf::strbuf(ptr(ar), 16)
  @alloc(ar) hs := 40
  ps := get(isize, ar, hs)
  h := alloc_into(u64, ar, 2)
  p := get(u64, ar, h)
  return u64(deref(ps)) + deref(p)
}
