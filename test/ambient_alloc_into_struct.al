## e2e — `alloc_into` for a STRUCT value end to end through the ambient allocator surface (D84).
## `alloc_into(P, ar, P(x = 40, y = 2))` allocates a two-word struct in the arena, stores it whole
## (the `deref(p) = init` value-model store, up-growing §4), and returns its `Handle`; the value is
## recovered with `s := deref(get(P, ar, h))` — a whole-struct copy out of the arena — and its
## fields summed (40 + 2 = 42). The `alloc::strbuf::…` reference transitively injects the base
## `alloc` module so the bare `arena_over`/`alloc_into`/`get` resolve. Guards the struct store inside
## `alloc_into` + the generic `get` → `deref` struct-copy read. (Direct field access through the raw
## `get` pointer — `deref(get(…)).x` — still needs the ptr-to-struct ek7 binding for a generic-return
## pointer; the whole-struct copy here is the working idiom.) Self-contained, like `ambient_strbuf`.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

P := struct { x : u64, y : u64 }

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  ## trigger base/alloc injection transitively via the alloc::strbuf lib module:
  mut sb := alloc::strbuf::strbuf(ptr(ar), 16)
  h := alloc_into(P, ar, P(x = 40, y = 2))
  s := deref(get(P, ar, h))
  return s.x + s.y
}
