## e2e (generic-container aggregate-payload delivery): reading a MULTI-WORD STRUCT element from a
## `Slice(V)` whose backing is arena/mmap memory (the `omap_values` shape). Previously a `v := vs[i]`
## whole-element read delivered only ONE word (the `Slice(T)` VALUE index path was word-element-only),
## so a struct-wider-than-one-word value type read zeros/garbage — this blocked `alloc::omap` (and any
## generic container) with a struct value. Now `index_value_layout`/`emit_elem_copy_in` copy the whole
## element UPWARD through the slice's data pointer (stride = the element struct's word count), and a
## generic call returning `Slice(<typeparam>)` records the SUBSTITUTED element (`Slice(Rec)`) so the
## element type is known at the read site. Exercises BOTH element 0 and element 1 (stride-aware).
om := alloc::omap
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
Rec := struct { a : i64, b : i64 }
lt := fn(a : u64, b : u64) -> bool { a < b }
main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut m := om::omap(u64, Rec, ptr(ar), 4)
  ## insert in ASCENDING key order (each appends at the tail — no value-array shift, so this
  ## exercises the Slice(struct) element READ, not omap's separate multi-word-value shift follow-up):
  ## key 10 -> Rec(3,4) at index 0, key 20 -> Rec(15,20) at index 1.
  om::omap_insert(u64, Rec, m, 10, Rec(a = 3, b = 4), lt).expect("i1")
  om::omap_insert(u64, Rec, m, 20, Rec(a = 15, b = 20), lt).expect("i2")
  vs := om::omap_values(u64, Rec, ptr(m))   ## Slice(Rec) view over the arena value block
  v0 := vs[0]                                ## element 0 = Rec(3, 4)
  v1 := vs[1]                                ## element 1 = Rec(15, 20) — stride-aware
  u64(v0.a + v0.b + v1.a + v1.b)             ## (3 + 4) + (15 + 20) = 42
}
