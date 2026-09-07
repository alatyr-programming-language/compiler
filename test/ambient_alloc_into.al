## e2e — the ambient allocator surface for a SCALAR value, in BOTH spellings, end to end. A raw
## `mmap` arena is wrapped by `arena_over`; the `alloc::strbuf::…` reference transitively injects the
## base `alloc` module (this file's distinguishing injection route — `ambient_alloc_scalar` and
## `ambient_alloc_attr` cover the standalone `@alloc`-forced route instead). `get` exchanges a handle
## for a scoped pointer whose deref recovers the stored value. Guards the value-model store
## `deref(p) = init` and the by-ref handle bridge inside `alloc_into` (an explicit `Handle(T)` literal
## so `get` receives it by reference — see lib/base/alloc.al). Self-contained (no `std::os`).
##
## SPELLING 1 (line 37) — `@alloc(ar) hs := 40`, the language surface Memory §2.4 specifies. The
## parser desugars it to `alloc_into(isize, ar, 40)` through a SYNTHESIZED callee span, so no user
## source names `alloc_into`. Issue #524 keeps `alloc_into` private on exactly that ground: Modules
## §3 line 73 scopes visibility to who may *name* a declaration, and the Stdlib appendix defines no
## `alloc_into` identifier.
##
## SPELLING 2 (line 39) — the BARE `alloc_into(u64, ar, 2)` call from USER source, and the reason
## this row is now a REJECT. It was kept here deliberately as the instance of the #403 visibility
## hole inside our own corpus: the `pub` test used to be consulted only in the qualified arm of
## `sema.al`'s resolver, so this unqualified reference to a private base declaration resolved, and
## the file built and ran to 42 (= 40 + 2). #403 makes §3 a property of the declaration rather than
## of the spelling, so the bare name is refused with the same located diagnostic the qualified
## spelling already produced. The accept half is covered by `ambient_alloc_scalar`, and
## `test/reject_base_private_alloc_into.al` locks the qualified spelling.
##
## SPELLING 1 remains the load-bearing half of THIS row: the `@alloc` desugar must NOT be refused.
## Modules §3 line 73 scopes visibility to who may *name* a declaration, and the desugar's callee span
## is synthesized, so it names nothing. If that exemption regressed, the diagnostic would move to the
## `@alloc` line instead — which is why this fixture asserts the exact line of the refusal.
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
