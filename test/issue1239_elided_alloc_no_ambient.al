## e2e / issue #1239 — an elided allocator with NO ambient in scope is refused, not defaulted to null.
##
## Functions §5.5 resolves an elided allocator in exactly four steps: the nearest enclosing
## `alloc::with`, then the enclosing function's OWN `alloc` parameter, then a §5.1 default, and
## otherwise "this is a compile error". Memory §5.2.1 states the same from the other side: "an
## allocating site with no resolvable ambient and no default is a compile error, never a hidden
## heap". Step (4) was missing: the elision pass simply dropped the argument.
##
## Measured on `58a80376` (omen, native x86_64): `build` rc **0** — the call was emitted with one
## argument fewer than the callee takes, so the arena slot held whatever the caller's register
## happened to hold, and the program ran with an arbitrary allocator instead of being refused. An
## arena in a local named `ar` is NOT ambient: §5.5 names only the three sources above, and a
## local is not one of them.
##
## The refusal is located at the CALL, which is where the author either opens an `alloc::with`
## scope or passes the allocator explicitly.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(std::sysno::MMAP, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut v := alloc::vec::with_capacity(u64, 16)
  alloc::vec::push(u64, v, 10).expect("push")
  return 42
}
## expect: reject "allocator required" "at line 24"
