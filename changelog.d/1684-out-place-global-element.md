- **An `out` / `in out` scalar bound to a module global or an array element reaches that place
  (#1684).** Functions §2.3 binds an `in out` parameter by a place argument — "a place-expression the
  callee reads and writes **in place**" — and requires it to be a mutable place (Memory §3), which an
  element of a `mut` array and a `mut` module global both are. Neither was written: the x86_64 emitter
  passed the address of the caller's first frame word for a global, so `give(g)` stored 10 into the
  caller's frame while `g` kept its old value and `g + 12` answered 12 where 22 was due, and it passed
  the element's VALUE for an array element, so `put(a[0])` stored through the integer 1 and died with
  SIGSEGV. Both now pass the place's own address — the global's `.data` label, the element address the
  index machinery already composes for every base — so the callee's write is visible to the caller. A
  name that is neither a bound local nor a `mut` global is refused with a located diagnostic instead of
  silently addressing frame slot 0. The shared IR declines these signatures, so this is the legacy
  emitter honouring the same rule; an element of a module-global array keeps its located refusal.
