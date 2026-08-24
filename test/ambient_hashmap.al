## e2e — the flagship generic `alloc::hashmap` container end to end through the AMBIENT path (no Rust
## seed). This is the capstone of the ambient-stdlib work: a 2-type-param generic (`HashMap(K, V)`)
## whose `insert`/`get` call `hash(key)` (an IMPLICIT-type-arg generic — `derive::hash(T, v)` with T
## omitted, inferred u64 from the key param + instantiated `derive__hash__u64`) and `eq(existing, key)`
## (resolved to the CONCRETE `cmp::eq(u64, u64)` overload by arity+type, not `derive::eq(T,a,b)`).
## Exercises: derive in the ambient prelude, per-signature overload mangling (cmp `eq__u64`), and
## implicit-type-arg generic-call inference (both the mono pre-pass + the emit call label). Insert
## 7 -> 42, read it back; a correct Some(42) exits 42. Raw `@abi(syscall)` mmap so it is self-contained.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut m := alloc::hashmap::new(u64, u64, ptr(ar))
  alloc::hashmap::hashmap_insert(u64, u64, ptr(m), ar, 7, 42).expect("insert")
  rr := alloc::hashmap::hashmap_get(u64, u64, ptr(m), ar, 7)
  match rr {
    Option::Some(v) => { u64(v) }
    Option::None => { 1 }
  }
}
