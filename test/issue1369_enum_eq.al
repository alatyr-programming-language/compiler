## #1369 — the structural `eq` (Stdlib appendix §2.6: two enum values are equal exactly when they are
## the same variant with equal payloads; Comptime §5.5: `T.(v)(p)` binds the whole payload, a TUPLE
## when the variant has several components) and a `HashMap` keyed by an enum. Two defects:
## the derive compared only the FIRST payload word (`B(3, -9)` equalled `B(3, -8)`), and a unit
## variant compared a payload word it never had; and inside a generic instance
## `existing := deref(key_at(K, …))` at an enum `K` bound one scalar word, which `eq(existing, key)`
## then passed as the tag VALUE to the by-reference enum parameter. NON-VACUOUS: on the parent
## `7cb5c053` (x86_64) this program exits 11 (the tuple payload), and every map case stops with
## SIGSEGV (rc 139) once the payload cases are removed.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

E0 := enum { Red, Green, Blue }
EN := enum { A(u64), B(u8, i64), C }

## a generic copy out of a pointer, the shape the map's probe loop uses
same_at := fn(K : type, p : ptr(K), k : K) -> bool {
  x := deref(p)
  eq(x, k)
}

main := fn() -> u64 {
  ## the structural `eq`, called directly
  if not eq(E0, E0.Green, E0.Green) { return 10 }
  if eq(EN, EN.B(3, 0 - 9), EN.B(3, 0 - 8)) { return 11 }
  if eq(EN, EN.B(3, 0 - 9), EN.B(4, 0 - 9)) { return 12 }
  if not eq(EN, EN.B(3, 0 - 9), EN.B(3, 0 - 9)) { return 13 }
  if not eq(EN, EN.C, EN.C) { return 14 }
  if eq(EN, EN.C, EN.A(0)) { return 15 }
  if eq(Option(u64), Option(u64).Some(3), Option(u64).None) { return 16 }
  if not eq(Option(ptr(u64)), Option(ptr(u64)).None, Option(ptr(u64)).None) { return 19 }
  ## through a generic local copied out of a pointer
  mut e := EN.B(3, 0 - 9)
  if not same_at(EN, ptr(e), EN.B(3, 0 - 9)) { return 17 }
  if same_at(EN, ptr(e), EN.B(3, 0 - 8)) { return 18 }

  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(std::sysno::MMAP, 0, 262144, 3, 34, bitcast(usize, neg1), 0)
  mut ar := arena_over(unchecked bitcast(ptr(mut bits8), bitcast(usize, r)), 262144)

  ## a payload-free enum key: inserting an existing key overwrites it
  mut m0 := alloc::hashmap::new(E0, u64, ptr(ar))
  alloc::hashmap::hashmap_insert(E0, u64, ptr(m0), ar, E0.Red, 1).expect("insert")
  alloc::hashmap::hashmap_insert(E0, u64, ptr(m0), ar, E0.Green, 2).expect("insert")
  alloc::hashmap::hashmap_insert(E0, u64, ptr(m0), ar, E0.Green, 3).expect("insert")
  if alloc::hashmap::len(E0, u64, ptr(m0), ar) != 2 { return 20 }
  g0 := alloc::hashmap::hashmap_get(E0, u64, ptr(m0), ar, E0.Green)
  match g0 {
    Option::Some(v) => { if v != 3 { return 21 } }
    Option::None => { return 22 }
  }
  if alloc::hashmap::contains(E0, u64, ptr(m0), ar, E0.Blue) { return 23 }

  ## a payload enum key, including two keys that differ only in the second component (non-negative:
  ## hashing a negative signed leaf traps, #1304)
  mut mn := alloc::hashmap::new(EN, u64, ptr(ar))
  alloc::hashmap::hashmap_insert(EN, u64, ptr(mn), ar, EN.B(3, 9), 4).expect("insert")
  alloc::hashmap::hashmap_insert(EN, u64, ptr(mn), ar, EN.B(3, 8), 5).expect("insert")
  alloc::hashmap::hashmap_insert(EN, u64, ptr(mn), ar, EN.C, 6).expect("insert")
  alloc::hashmap::hashmap_insert(EN, u64, ptr(mn), ar, EN.C, 7).expect("insert")
  if alloc::hashmap::len(EN, u64, ptr(mn), ar) != 3 { return 30 }
  gn := alloc::hashmap::hashmap_get(EN, u64, ptr(mn), ar, EN.B(3, 8))
  match gn {
    Option::Some(v) => { if v != 5 { return 31 } }
    Option::None => { return 32 }
  }

  ## library enum instances as keys
  mut mo := alloc::hashmap::new(Option(u64), u64, ptr(ar))
  alloc::hashmap::hashmap_insert(Option(u64), u64, ptr(mo), ar, Option(u64).Some(9), 8).expect("insert")
  alloc::hashmap::hashmap_insert(Option(u64), u64, ptr(mo), ar, Option(u64).None, 9).expect("insert")
  alloc::hashmap::hashmap_insert(Option(u64), u64, ptr(mo), ar, Option(u64).Some(9), 10).expect("insert")
  if alloc::hashmap::len(Option(u64), u64, ptr(mo), ar) != 2 { return 40 }
  if not alloc::hashmap::contains(Option(u64), u64, ptr(mo), ar, Option(u64).None) { return 41 }
  mut cell : u64 = 0
  mut mp := alloc::hashmap::new(Option(ptr(u64)), u64, ptr(ar))
  alloc::hashmap::hashmap_insert(Option(ptr(u64)), u64, ptr(mp), ar, Option(ptr(u64)).Some(ptr(cell)), 11).expect("insert")
  alloc::hashmap::hashmap_insert(Option(ptr(u64)), u64, ptr(mp), ar, Option(ptr(u64)).None, 12).expect("insert")
  alloc::hashmap::hashmap_insert(Option(ptr(u64)), u64, ptr(mp), ar, Option(ptr(u64)).Some(ptr(cell)), 13).expect("insert")
  if alloc::hashmap::len(Option(ptr(u64)), u64, ptr(mp), ar) != 2 { return 50 }
  if not alloc::hashmap::contains(Option(ptr(u64)), u64, ptr(mp), ar, Option(ptr(u64)).None) { return 51 }
  42
}
## expect: run 42
