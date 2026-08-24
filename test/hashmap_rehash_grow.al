## e2e (Comptime §3.3 regression lock). `alloc::hashmap::rehash` hashed its re-inserted keys through
## `hash(k)` where `k` is a LOCAL bound from `deref(ptr(mut K))` — a shape whose comptime type
## argument is NOT inferable, so the call silently took `k` ITSELF for the erased type argument and
## passed NO value at all: every re-inserted key was hashed from a garbage register. A SILENT wrong
## value that only surfaces once a map outgrows its initial capacity (~75% load), which no existing
## fixture reached — the corpus is full of tiny maps. `hash(K, k)` now spells the type argument, and
## the compiler REJECTS an un-inferable omitted type argument instead of dropping a value argument.
##
## CONTENT, not count: insert 24 distinct keys (forcing several doublings of the default 8-bucket
## table) with values that are a FUNCTION of the key, then read every one back and check the value
## MATCHES its key. A rehash that scrambled the buckets loses or mis-pairs entries, so a bare
## "how many are present" check would not catch it. Returns 42.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 262144, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 262144)
  mut m := alloc::hashmap::new(u64, u64, ptr(ar))
  mut i : u64 = 0
  while i < 24 {
    alloc::hashmap::hashmap_insert(u64, u64, ptr(m), ar, i * 7 + 3, i * 11 + 5).expect("insert")
    i += 1
  }
  mut ok : u64 = 0
  mut j : u64 = 0
  while j < 24 {
    g := alloc::hashmap::hashmap_get(u64, u64, ptr(m), ar, j * 7 + 3)
    match g {
      Option::Some(v) => { if u64(v) == j * 11 + 5 { ok += 1 } }
      Option::None => {}
    }
    j += 1
  }
  if ok == 24 { return 42 }
  ok
}
