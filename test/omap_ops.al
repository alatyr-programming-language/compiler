## e2e — alloc::omap ordered map: parallel sorted key/value arrays, insert keeps them sorted by key via a
## caller `less` comparator, a duplicate key OVERWRITES its value, and growth (from cap 2) preserves every
## KEY and VALUE across the doublings. Insert six pairs out of order forcing two grows, overwrite one, then
## verify get/contains/len and the sorted key+value slices. Returns 42 iff all exact.
##
## NB: `omap_get` returns `Option(V)` (V generic); its payload is read via `match` here, not `.expect()` —
## extracting a generic-type-param payload through `.expect()` mis-delivers today (a separate stdlib/codegen
## corner, tracked). `match` over the generic Option delivers the payload correctly.
om := alloc::omap
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

lt := fn(a : u64, b : u64) -> bool { a < b }

## `match`-based get→value with a sentinel for absent (the tests never query an absent key through this).
getv := fn(m : ptr(om::OMap(u64, u64)), key : u64) -> u64 {
  match om::omap_get(u64, u64, m, key, lt) {
    Option.Some(x) => { x }
    Option.None => { 0 }
  }
}

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut m := om::omap(u64, u64, ptr(ar), 2)          ## cap 2 → inserting 6 forces two doublings

  ## values = key + 1000; inserted out of key order.
  om::omap_insert(u64, u64, m, 50, 1050, lt).expect("i")
  om::omap_insert(u64, u64, m, 30, 1030, lt).expect("i")
  om::omap_insert(u64, u64, m, 70, 1070, lt).expect("i")   ## grow here (len 2 -> cap 4)
  om::omap_insert(u64, u64, m, 10, 1010, lt).expect("i")
  om::omap_insert(u64, u64, m, 90, 1090, lt).expect("i")   ## grow here (len 4 -> cap 8)
  om::omap_insert(u64, u64, m, 20, 1020, lt).expect("i")

  if om::omap_len(u64, u64, ptr(m)) != 6 { return 1 }

  ## overwrite an existing key's value — returns Ok(false), len unchanged.
  added := om::omap_insert(u64, u64, m, 30, 9999, lt).expect("i")
  if added { return 2 }
  if om::omap_len(u64, u64, ptr(m)) != 6 { return 3 }

  ## every value survives the grows (the lost-value corner).
  if getv(ptr(m), 50) != 1050 { return 4 }
  if getv(ptr(m), 70) != 1070 { return 5 }
  if getv(ptr(m), 10) != 1010 { return 6 }
  if getv(ptr(m), 90) != 1090 { return 7 }
  if getv(ptr(m), 20) != 1020 { return 8 }
  if getv(ptr(m), 30) != 9999 { return 9 }   ## overwritten

  ## a missing key → None; contains reflects membership.
  match om::omap_get(u64, u64, ptr(m), 99, lt) {
    Option.Some(x) => { return 10 }
    Option.None => {}
  }
  if not om::omap_contains(u64, u64, ptr(m), 20, lt) { return 11 }
  if om::omap_contains(u64, u64, ptr(m), 99, lt) { return 12 }

  ## sorted key slice ascending, and the value slice parallel to it (value i belongs to key i).
  ks := om::omap_keys(u64, u64, ptr(m))
  if ks[0] != 10 { return 13 }
  if ks[1] != 20 { return 14 }
  if ks[2] != 30 { return 15 }
  if ks[3] != 50 { return 16 }
  if ks[4] != 70 { return 17 }
  if ks[5] != 90 { return 18 }

  vs := om::omap_values(u64, u64, ptr(m))
  if vs[0] != 1010 { return 19 }
  if vs[1] != 1020 { return 20 }
  if vs[2] != 9999 { return 21 }   ## key 30's overwritten value, at key 30's sorted slot
  if vs[3] != 1050 { return 22 }
  if vs[4] != 1070 { return 23 }
  if vs[5] != 1090 { return 24 }

  return 42
}
