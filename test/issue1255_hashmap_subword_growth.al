## e2e / issue #1255 — a `HashMap` of a sub-word value or key returns what was inserted, after growth.
##
## Stdlib appendix §6: `get(k)` returns `Some` of the value last inserted under `k`. Inside the
## generic instance, `deref(val_at(K, V, m, a, i))` read and wrote 8 bytes whatever `V` was: the
## width of a `deref` through a pointer a CALL returns fell to the word default. A `u8` value read
## its neighbours into the result, and a rehash's store overwrote them, so the table was right only
## while the bytes after each slot were still zero. A sub-word key failed the same way.
##
## Each check owns a code from 10 up; 42 means all held.
##
## Parent `9acadf0b` (x86_64, omen): built rc 0, ran to 10 where 42 was due — `get` of a `u8` value
## after growth did not read back 157.
hashmap := alloc::hashmap
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  r := unchecked sys_mmap(std::sysno::MMAP, 0, 1048576, 3, 34, bitcast(usize, 0 - 1), 0)
  mut ar := arena_over(unchecked bitcast(ptr(mut bits8), bitcast(usize, r)), 1048576)

  ## the issue's program: 20 entries, past the initial capacity
  mut m := hashmap::new(u64, u8, ptr(ar))
  mut i : u64 = 0
  while i < 20 {
    p := hashmap::insert(u64, u8, ptr(m), ar, i * 31 + 5, u8(150 + i))
    i += 1
  }
  o := hashmap::get(u64, u8, ptr(m), ar, 7 * 31 + 5)
  match o {
    Option::Some(x) => { if x != 157 { return 10 } }
    Option::None => { return 11 }
  }

  ## every value back, `u16` and `i8` values
  mut mw := hashmap::new(u64, u16, ptr(ar))
  mut ms := hashmap::new(u64, i8, ptr(ar))
  i = 0
  while i < 40 {
    pw := hashmap::insert(u64, u16, ptr(mw), ar, i * 31 + 5, u16(1000 + i))
    ps := hashmap::insert(u64, i8, ptr(ms), ar, i * 31 + 5, i8(i) - 20)
    i += 1
  }
  i = 0
  while i < 40 {
    ow := hashmap::get(u64, u16, ptr(mw), ar, i * 31 + 5)
    match ow {
      Option::Some(x) => { if x != u16(1000 + i) { return 12 } }
      Option::None => { return 13 }
    }
    os := hashmap::get(u64, i8, ptr(ms), ar, i * 31 + 5)
    match os {
      Option::Some(x) => { if x != i8(i) - 20 { return 14 } }
      Option::None => { return 15 }
    }
    i += 1
  }

  ## a `u16` key
  mut mk := hashmap::new(u16, u64, ptr(ar))
  i = 0
  while i < 40 {
    pk := hashmap::insert(u16, u64, ptr(mk), ar, u16(i + 1), i * 3)
    i += 1
  }
  i = 0
  while i < 40 {
    ok := hashmap::get(u16, u64, ptr(mk), ar, u16(i + 1))
    match ok {
      Option::Some(x) => { if x != i * 3 { return 16 } }
      Option::None => { return 17 }
    }
    i += 1
  }
  42
}
