## e2e — alloc::deque double-ended queue: push/pop at both ends, wrap-around, and growth (starts at
## cap 2 so push_front after two push_backs forces a doubling + re-linearize). Verifies front/back/dq_at
## reads and that the logical order survives the grow. Returns 42 iff every step is exact.
dq := alloc::deque
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

some_is := fn(o : Option(u64), want : u64) -> bool {
  match o {
    Option::Some(x) => { x == want }
    Option::None => { false }
  }
}

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut d := dq::deque(u64, ptr(ar), 2)

  dq::push_back(u64, d, 10).expect("pb")     ## [10]
  dq::push_back(u64, d, 20).expect("pb")     ## [10,20]  (full at cap 2)
  dq::push_front(u64, d, 5).expect("pf")     ## [5,10,20] (forces grow to cap 4, re-linearize)

  if dq::dq_len(u64, ptr(d)) != 3 { return 1 }
  f := dq::front(u64, ptr(d))
  if not some_is(f, 5) { return 2 }
  b := dq::back(u64, ptr(d))
  if not some_is(b, 20) { return 3 }
  a1 := dq::dq_at(u64, ptr(d), 1)
  if not some_is(a1, 10) { return 4 }

  pf := dq::pop_front(u64, d)                 ## 5 -> [10,20]
  if not some_is(pf, 5) { return 5 }
  pb := dq::pop_back(u64, d)                  ## 20 -> [10]
  if not some_is(pb, 20) { return 6 }
  if dq::dq_len(u64, ptr(d)) != 1 { return 7 }

  dq::push_back(u64, d, 30).expect("pb")      ## [10,30]
  dq::push_front(u64, d, 1).expect("pf")      ## [1,10,30]
  a0 := dq::dq_at(u64, ptr(d), 0)
  if not some_is(a0, 1) { return 8 }
  a2 := dq::dq_at(u64, ptr(d), 2)
  if not some_is(a2, 30) { return 9 }

  oob := dq::dq_at(u64, ptr(d), 3)
  match oob { Option::Some(x) => { return 10 } Option::None => {} }

  return 42
}
