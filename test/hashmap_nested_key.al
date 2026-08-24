## e2e — NESTED-aggregate structural `eq` through the derive (regression for the nested word-0-only
## silent miscompile). `HashMap(Outer, u64)` with `Outer` holding a NESTED `Inner` struct: the derive
## `eq(Outer, a, b)` must recurse into the nested field and compare ALL its words, not word 0 only.
## Two keys share word 0 (`Inner.a == 1`) but differ in the NESTED word (`Inner.b`: 2 vs 999). A
## word-0-only compare (the old bare-operator bug inside the derive) would treat them as the SAME key
## → the lookup of `kd` would wrongly HIT. With the derive recursing explicitly (`eq(f.type, …)`), the
## nested word is compared, so `kd` MISSES (None) and the exact key `k` HITS with 42.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

Inner := struct { a : u64, b : u64 }
Outer := struct { p : Inner, q : u64 }

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut m := alloc::hashmap::new(Outer, u64, ptr(ar))
  k := Outer(p = Inner(a = 1, b = 2), q = 3)
  kd := Outer(p = Inner(a = 1, b = 999), q = 3)   ## shares word 0, differs in NESTED word b
  alloc::hashmap::hashmap_insert(Outer, u64, ptr(m), ar, k, 42).expect("insert")
  rr := alloc::hashmap::hashmap_get(Outer, u64, ptr(m), ar, kd)
  match rr {
    Option::Some(v) => { 100 }   ## WRONG: nested word ignored → a false hit
    Option::None => {
      rk := alloc::hashmap::hashmap_get(Outer, u64, ptr(m), ar, k)
      match rk { Option::Some(v) => { u64(v) } Option::None => { 1 } }
    }
  }
}
