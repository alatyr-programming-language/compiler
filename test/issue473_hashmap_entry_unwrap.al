## e2e — Issue #473, the live standard-library consequence: `alloc::hashmap::next` returns
## `Option(Entry(K, V))` and `Entry` is a GENERIC struct (Stdlib appendix §6 / §2.4), so opening
## that option with `unwrap` went through the same generic enum-value-param substitution as the
## minimal case. The whole `Entry` must arrive, not its first word.
##
## Failure-first on parent 8b422be (x86_64, default build path): builds rc=0 and exits 5 — `e.val`
## reads back as 5, the KEY, not the value 42. The `match` walk over the SAME `next` call is the
## control and is already correct on the parent; the two are checked against each other here.
##
## Only `hashmap_iter` is used, never the `iter` map-entry/identity overload pair, so this program
## does not depend on the separate same-symbol generic-overload defect (#472). `Entry(u64, u64)` is
## spelled unqualified for the same reason: a QUALIFIED generic type-ARGUMENT is mangled with its
## `::` separators intact, so `unwrap(alloc::hashmap::Entry(u64, u64), …)` emits a label the
## assembler refuses — a separate pre-existing defect that this fixture must not depend on.
## Every rejection code is distinct and below 126; nothing is summed into one total.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 262144, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 262144)

  mut m := alloc::hashmap::new(u64, u64, ptr(ar))
  alloc::hashmap::hashmap_insert(u64, u64, ptr(m), ar, 5, 42).expect("insert 5")

  ## ---- the `unwrap` walk: the whole `Entry(u64, u64)` must arrive -------------------------
  mut c1 := alloc::hashmap::hashmap_iter(u64, u64, ptr(m), ar)
  e := unwrap(Entry(u64, u64), alloc::hashmap::next(u64, u64, c1))
  if e.key != 5 {
    if e.key == 0 { return 1 }
    if e.key == 42 { return 2 }
    return 3
  }
  if e.val != 42 {
    if e.val == 0 { return 4 }
    if e.val == 5 { return 5 }
    return 6
  }

  ## ---- CONTROL: the identical walk through `match` — correct on the parent ----------------
  mut c2 := alloc::hashmap::hashmap_iter(u64, u64, ptr(m), ar)
  match alloc::hashmap::next(u64, u64, c2) {
    Option::Some(x) => {
      if x.key != 5 {
        if x.key == 0 { return 10 }
        if x.key == 42 { return 11 }
        return 12
      }
      if x.val != 42 {
        if x.val == 0 { return 13 }
        if x.val == 5 { return 14 }
        return 15
      }
    }
    Option::None => { return 16 }
  }

  ## ---- the walk ENDS after the single entry, through `unwrap`'s absence test --------------
  mut c3 := alloc::hashmap::hashmap_iter(u64, u64, ptr(m), ar)
  first := alloc::hashmap::next(u64, u64, c3)
  if is_some(Entry(u64, u64), first) == false { return 20 }
  second := alloc::hashmap::next(u64, u64, c3)
  if is_none(Entry(u64, u64), second) == false { return 21 }

  100 - 58
}
