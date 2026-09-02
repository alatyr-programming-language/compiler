## e2e — `HashMap(str, V)`: a `str` KEY, hashed and compared by CONTENT (Stdlib §2.6 / §6).
##
## §6 requires a `HashMap` key to satisfy `Hash` and `Eq`, and §2.6 requires `Hash` to be
## CONSISTENT with `Eq` — equal values hash equally. The derived `Eq` for a `str` bottoms out at the
## structural derive's `_` arm `a == b`, which the lower compares by CONTENT, so the derived `Hash`
## for a `str` must be the CONTENT hash. It was not: `typeinfo(str)` is the opaque §4.1 `Str` kind,
## which the structural `hash(T, v)` had no arm for, so it fell through to `u64(v)` and rejected the
## two-word view as a non-scalar conversion operand. And inside a `HashMap(str, V)` INSTANCE the key
## parameter `key : K` is a `str` view whose slot carries no readable annotation, so `hash(key)` /
## `eq(existing, key)` could infer no comptime type argument either. Both together made every
## `str`-keyed map a valid program the compiler refused to build (Comptime §3.3 reject).
##
## The two views `k1` / `k2` hold the SAME five bytes in TWO SEPARATE mmap allocations, so a hash or
## an equality that compared the `{ptr, len}` words instead of the bytes cannot pass: the fixture
## first PROVES the pointers differ (code 100) and then requires `k2` to find what `k1` inserted.
## The seventh insert crosses the ~75% load factor of the default 8 buckets, so the map REHASHES —
## `rehash` spells `hash(K, k)` explicitly while `insert`/`get` call the implicit `hash(key)`, and a
## fix that routed only one of the two would lose every key at that point (codes 110/111).
##
## Every failure has its own code from 100 up; success is 42.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

## one fresh anonymous mapping (a distinct allocation per call)
page := fn(n : usize) -> usize {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, n, 3, 34, bitcast(usize, neg1), 0)
  unchecked bitcast(usize, r)
}

## write "alpha" at `base` and return a `str` VIEW over exactly those five bytes
write_alpha := fn(base : usize) -> str {
  p := unchecked bitcast(ptr(mut u8), base)
  deref(p) = 97
  deref(unchecked bitcast(ptr(mut u8), base + 1)) = 108
  deref(unchecked bitcast(ptr(mut u8), base + 2)) = 112
  deref(unchecked bitcast(ptr(mut u8), base + 3)) = 104
  deref(unchecked bitcast(ptr(mut u8), base + 4)) = 97
  str_at(unchecked bitcast(ptr(u8), base), 5)
}

main := fn() -> u64 {
  ap := page(65536)
  b1 := page(4096)
  b2 := page(4096)
  bp := unchecked bitcast(ptr(mut bits8), ap)
  mut ar := arena_over(bp, 65536)

  k1 : str = write_alpha(b1)
  k2 : str = write_alpha(b2)

  ## the two keys are equal CONTENT in DISTINCT allocations — otherwise the test is vacuous
  if bitcast(usize, k1.ptr) == bitcast(usize, k2.ptr) { return 100 }
  if k1.len != 5 { return 101 }
  if k2.len != 5 { return 102 }
  if not str_eq(k1, k2) { return 103 }
  ## §2.6: Hash consistent with Eq — equal content must hash equally, and the hash must depend on
  ## the BYTES (a {ptr,len} hash would differ here, and a constant hash would equal "alpha"'s twin
  ## for every other string too).
  if hash(k1) != hash(k2) { return 104 }
  other : str = "beta"
  if hash(k1) == hash(other) { return 105 }

  mut m := alloc::hashmap::new(str, u64, ptr(ar))
  alloc::hashmap::insert(str, u64, ptr(m), ar, k1, 11).expect("insert k1")
  if alloc::hashmap::len(str, u64, ptr(m), ar) != 1 { return 106 }

  ## the OTHER allocation must find it, and must not be treated as a second key
  if not alloc::hashmap::contains(str, u64, ptr(m), ar, k2) { return 107 }
  match alloc::hashmap::get(str, u64, ptr(m), ar, k2) {
    Option::Some(v) => { if u64(v) != 11 { return 108 } }
    Option::None => { return 109 }
  }
  alloc::hashmap::insert(str, u64, ptr(m), ar, k2, 23).expect("overwrite via k2")
  if alloc::hashmap::len(str, u64, ptr(m), ar) != 1 { return 110 }
  match alloc::hashmap::get(str, u64, ptr(m), ar, k1) {
    Option::Some(v) => { if u64(v) != 23 { return 111 } }
    Option::None => { return 112 }
  }

  ## absent keys stay absent
  if alloc::hashmap::contains(str, u64, ptr(m), ar, "alph") { return 113 }
  if alloc::hashmap::contains(str, u64, ptr(m), ar, "alphaa") { return 114 }
  if alloc::hashmap::contains(str, u64, ptr(m), ar, "beta") { return 115 }

  ## six more keys: the seventh entry crosses (live+1)*4 > cap*3 for cap 8, so the map REHASHES.
  alloc::hashmap::insert(str, u64, ptr(m), ar, "b", 2).expect("b")
  alloc::hashmap::insert(str, u64, ptr(m), ar, "cc", 3).expect("cc")
  alloc::hashmap::insert(str, u64, ptr(m), ar, "ddd", 4).expect("ddd")
  alloc::hashmap::insert(str, u64, ptr(m), ar, "eeee", 5).expect("eeee")
  alloc::hashmap::insert(str, u64, ptr(m), ar, "fffff", 6).expect("fffff")
  alloc::hashmap::insert(str, u64, ptr(m), ar, "gggggg", 7).expect("gggggg")
  if alloc::hashmap::len(str, u64, ptr(m), ar) != 7 { return 116 }

  ## after the rehash every key must still resolve, checked ONE AT A TIME (no summed discriminator)
  match alloc::hashmap::get(str, u64, ptr(m), ar, k2) {
    Option::Some(v) => { if u64(v) != 23 { return 117 } }
    Option::None => { return 118 }
  }
  match alloc::hashmap::get(str, u64, ptr(m), ar, "b") {
    Option::Some(v) => { if u64(v) != 2 { return 119 } }
    Option::None => { return 120 }
  }
  match alloc::hashmap::get(str, u64, ptr(m), ar, "cc") {
    Option::Some(v) => { if u64(v) != 3 { return 121 } }
    Option::None => { return 122 }
  }
  match alloc::hashmap::get(str, u64, ptr(m), ar, "gggggg") {
    Option::Some(v) => { if u64(v) != 7 { return 123 } }
    Option::None => { return 124 }
  }
  if alloc::hashmap::contains(str, u64, ptr(m), ar, "hhhhhhh") { return 125 }

  42
}
