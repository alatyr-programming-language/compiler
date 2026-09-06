## e2e (#472) — the LIVE trigger in the standard library, and criterion 5 of the issue.
## `lib/alloc/hashmap.al` declares BOTH `iter` overloads of Stdlib appendix §2.4: the map entry
## point `iter(K, V, m : ptr(HashMap(K, V)), a : Arena)` and the Iterator-protocol identity
## `iter(K, V, it : HashMapIter(K, V))`. Using both at the SAME `(K, V)` in one program made the two
## share one linker symbol. The BARE spelling is used deliberately: it reaches both overloads on the
## parent without any visibility change, which is what makes this independent of #404's `pub`
## markers (#403 — `pub` is enforced only on qualified paths).
##
## Parent verdict: build rc=13, the assembler refused a duplicate `alloc__hashmap__iter__u64__u64`.
## Fixed verdict: 42 — insert 7 -> 42, take the iterator, pass it through the protocol identity,
## and read the first live entry's value back. Raw `@abi(syscall)` mmap so the fixture is
## self-contained, matching `ambient_hashmap.al`.

sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut m := alloc::hashmap::new(u64, u64, ptr(ar))
  alloc::hashmap::hashmap_insert(u64, u64, ptr(m), ar, 7, 42).expect("insert")
  ## the MAP entry point (4 args) …
  mut it := iter(u64, u64, ptr(m), ar)
  ## … then the protocol IDENTITY (3 args) over the iterator it returned.
  mut it2 := iter(u64, u64, it)
  match next(u64, u64, it2) {
    Option::Some(e) => { u64(e.val) }
    Option::None => { 10 }
  }
}
