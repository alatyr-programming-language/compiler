## e2e CONTROL — Issue #404 / Modules §3 + Stdlib appendix §2.4: publishing `alloc::hashmap`'s
## `iter`/`next` widens who may NAME them; it must not change which declaration a call site
## RESOLVES to. This fixture is deliberately GREEN ON THE PARENT TOO (8370bd2) — that is what makes
## it a control. It answers 42 before and after the two `pub` markers, so a resolution change would
## show up here as a wrong value rather than as a rejection somewhere else.
##
## `alloc::hashmap` is pulled into the same compilation through its already-public `new` /
## `hashmap_insert` / `hashmap_get`, so the published `iter`/`next`/`Entry` names are genuinely in
## scope while this file declares its own:
##   * `iter`  — this file's overload keyed on `Beads`, versus `alloc::hashmap`'s two on
##               `ptr(HashMap(K, V))` and `HashMapIter(K, V)`;
##   * `next`  — same, and it is what the `for` desugar (Control Flow §6) must select;
##   * `Entry` — a user type whose spelling matches the base library's `pub Entry(K, V)`, but which
##               takes no type arguments and means this file's struct.
## Every rejection code is distinct and < 126, and nothing is summed into a single total.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

Beads := struct { n : u64 }

Entry := struct { tag : u64 }

iter := fn(b : Beads) -> Beads { Beads(n = b.n) }

next := fn(in out b : Beads) -> Option(u64) {
  if b.n >= 3 { return Option(u64).None }
  v := b.n
  b.n = b.n + 1
  Option(u64).Some(v * 10)
}

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)

  ## the alloc-tier map is in this compilation, through its already-public surface
  mut m := alloc::hashmap::new(u64, u64, ptr(ar))
  alloc::hashmap::hashmap_insert(u64, u64, ptr(m), ar, 5, 7).expect("insert 5")
  match alloc::hashmap::hashmap_get(u64, u64, ptr(m), ar, 5) {
    Option::Some(v) => { if u64(v) != 7 { return 1 } }
    Option::None => { return 2 }
  }

  ## the user's `iter` wins for the user's type
  mut b := Beads(n = 0)
  c := iter(b)
  if c.n != 0 { return 3 }

  ## the user's `next` wins, and yields the USER's values (10 * index), not map entries
  match next(b) {
    Option::Some(v) => { if v != 0 { return 4 } }
    Option::None => { return 5 }
  }
  match next(b) {
    Option::Some(v) => { if v != 10 { return 6 } }
    Option::None => { return 7 }
  }
  if b.n != 2 { return 8 }

  ## the user's `Entry` wins over `alloc::hashmap`'s `pub Entry(K, V)`: no type arguments, one field
  t := Entry(tag = 4)
  if t.tag != 4 { return 9 }

  ## the `for` desugar drives the USER's `next`: three yields, checked one index at a time
  mut k : u64 = 0
  mut u := Beads(n = 0)
  for v in u {
    if k == 0 and v != 0 { return 10 }
    if k == 1 and v != 10 { return 11 }
    if k == 2 and v != 20 { return 12 }
    k = k + 1
    if k > 3 { return 13 }
  }
  if k != 3 { return 14 }

  42
}
