## e2e — the `@alloc(a) x := init` storage attribute (Memory §2.4), the language surface over
## `alloc_into`, used STANDALONE (no explicit `alloc::` reference). The parser desugars
## `@alloc(ar) h := P(x = 40, y = 2)` to `h := alloc_into(ar, P(…))`, binding `h : Handle(P)`; the bare
## `@alloc` forces the base allocator prelude to be injected (arena_over / alloc_into / get), so the
## program is self-contained. The value is recovered with `s := deref(get(P, ar, h))` (a whole-struct
## copy out of the arena) and its fields summed (40 + 2 = 42). Guards the parser desugar (synthesized
## `alloc_into` callee span) + the `@alloc`-driven prelude injection, end to end.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

P := struct { x : u64, y : u64 }

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  @alloc(ar) h := P(x = 40, y = 2)
  s := deref(get(P, ar, h))
  return s.x + s.y
}
