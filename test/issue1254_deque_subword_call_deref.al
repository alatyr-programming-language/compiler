## e2e / issues #1254, #1255 — `dq_at`, `front` and `back` on a `Deque` of a sub-word element.
##
## Stdlib appendix §6: `dq_at(i)` returns `Some` of element `i`. `dq_at`, `front` and `back` read
## `deref(dq_elem(T, d, i))`, a `deref` through a pointer a CALL returns, and its width fell to the
## 8-byte default inside the generic instance: a `Deque(u8)` element read the 7 bytes after it, so it
## was right only while they were still zero. This is the read half of #1254. `push_front`,
## `pop_front` and `pop_back` go through a local bound from that call and are still open under #1254.
##
## Each check owns a code from 10 up; 42 means all held.
##
## Parent `9acadf0b` (x86_64, omen): built rc 0, ran to 10 where 42 was due — `dq_at(7)` was not 157.
deque := alloc::deque
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  r := unchecked sys_mmap(std::sysno::MMAP, 0, 1048576, 3, 34, bitcast(usize, 0 - 1), 0)
  mut ar := arena_over(unchecked bitcast(ptr(mut bits8), bitcast(usize, r)), 1048576)

  ## #1254's program: 20 pushes into capacity 2
  mut d := deque::deque(u8, ptr(ar), 2)
  mut i : u64 = 0
  while i < 20 {
    p := deque::push_back(u8, d, u8(150 + i))
    i += 1
  }
  o := deque::dq_at(u8, ptr(d), 7)
  match o {
    Option::Some(x) => { if x != 157 { return 10 } }
    Option::None => { return 11 }
  }

  ## every element, at `i16`, through `dq_at`, `front` and `back`
  mut e := deque::deque(i16, ptr(ar), 2)
  i = 0
  while i < 20 {
    q := deque::push_back(i16, e, i16(i) - 300)
    i += 1
  }
  i = 0
  while i < 20 {
    oe := deque::dq_at(i16, ptr(e), i)
    match oe {
      Option::Some(x) => { if x != i16(i) - 300 { return 12 } }
      Option::None => { return 13 }
    }
    i += 1
  }
  f := deque::front(i16, ptr(e))
  match f {
    Option::Some(x) => { if x != 0 - 300 { return 14 } }
    Option::None => { return 15 }
  }
  b := deque::back(i16, ptr(e))
  match b {
    Option::Some(x) => { if x != 0 - 281 { return 16 } }
    Option::None => { return 17 }
  }
  42
}
