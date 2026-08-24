## Appendix §160 surface lock: Vec capacity/get, Option get, and HashMap insert/get.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)

  mut v := alloc::vec::new(u64, ptr(ar))
  alloc::vec::push(u64, v, 40).expect("push")
  if alloc::vec::capacity(u64, ptr(v)) < 8 { return 1 }
  vg := alloc::vec::get(u64, ptr(v), 0)
  x := match vg { Option::Some(n) => n; Option::None => 0 }

  mut o := Option(u64).Some(2)
  op := Option::get(u64, ptr(o))
  y := match op { Option::Some(p) => deref(p); Option::None => 0 }

  mut m := alloc::hashmap::new(u64, u64, ptr(ar))
  alloc::hashmap::insert(u64, u64, ptr(m), ar, 7, 42).expect("insert")
  hm := alloc::hashmap::get(u64, u64, ptr(m), ar, 7)
  z := match hm { Option::Some(n) => n; Option::None => 0 }
  x + y + z
}
