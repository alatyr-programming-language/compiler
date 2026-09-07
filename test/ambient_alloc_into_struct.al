## e2e — the ambient allocator surface for a STRUCT value, in BOTH spellings, end to end. A two-word
## struct is allocated in a raw `mmap` arena wrapped by `arena_over`, stored whole (the
## `deref(p) = init` value-model store, up-growing §4), and recovered with `deref(get(P, ar, h))` — a
## whole-struct copy out of the arena. The `alloc::strbuf::…` reference transitively injects the base
## `alloc` module (this file's distinguishing injection route; `ambient_alloc_attr` covers the
## standalone `@alloc`-forced route). Guards the struct store inside `alloc_into` plus the generic
## `get` → `deref` struct-copy read. (Direct field access through the raw `get` pointer —
## `deref(get(…)).x` — still needs the ptr-to-struct ek7 binding for a generic-return pointer; the
## whole-struct copy here is the working idiom.) Self-contained, like `ambient_strbuf`.
##
## SPELLING 1 (line 34) — `@alloc(ar) ha := P(x = 30, y = 2)`, the Memory §2.4 storage attribute. The
## parser desugars it through a SYNTHESIZED `alloc_into` callee span, so no user source names
## `alloc_into`; issue #524 keeps it private on exactly that ground (Modules §3 line 73 scopes
## visibility to who may *name* a declaration).
##
## SPELLING 2 (line 36) — the BARE `alloc_into(P, ar, …)` call from USER source: an instance of the
## #403 visibility hole inside our own corpus, since the `pub` test is consulted only in the
## qualified arm of `sema.al`'s resolver. Kept DELIBERATELY as the row that flips from accept to
## reject when #403 lands, at which point this file becomes a reject fixture on the bare call and its
## accept half is already covered by `ambient_alloc_attr`. Do not "simplify" it away.
##
## 42 = (30 + 2) + (8 + 2). Either struct store dropping a word misses 42.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

P := struct { x : u64, y : u64 }

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  ## trigger base/alloc injection transitively via the alloc::strbuf lib module:
  mut sb := alloc::strbuf::strbuf(ptr(ar), 16)
  @alloc(ar) ha := P(x = 30, y = 2)
  sa := deref(get(P, ar, ha))
  h := alloc_into(P, ar, P(x = 8, y = 2))
  s := deref(get(P, ar, h))
  return sa.x + sa.y + s.x + s.y
}
