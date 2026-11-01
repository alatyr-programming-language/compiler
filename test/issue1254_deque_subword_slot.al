## e2e / issue #1254 — `push_front`, `pop_front` and `pop_back` on a `Deque` of a sub-word element.
##
## Stdlib appendix §6: `push_front(x)` makes `x` the front element; `pop_front` and `pop_back` return
## `Some` of the front and back element. All three go through a local bound from a call,
## `slot := dq_elem(T, ptr(d), i)`, then `deref(slot) = x` or `v := deref(slot)`. That local recorded no
## pointee type, so inside the generic instance both moves were 8 bytes wide: `push_front` wrote over
## the seven bytes after its slot (the elements already pushed), and a pop read them into the value.
## The `dq_at` / `front` / `back` half of #1254 (a `deref` straight through the call) is #1267's.
##
## Every value is read back through `pop_front` / `pop_back` only, so this fixture exercises the
## call-bound local and nothing else. Each check owns a code from 10 up; 42 means all held.
deque := alloc::deque
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  r := unchecked sys_mmap(std::sysno::MMAP, 0, 1048576, 3, 34, bitcast(usize, 0 - 1), 0)
  mut ar := arena_over(unchecked bitcast(ptr(mut bits8), bitcast(usize, r)), 1048576)

  ## u8: 20 × push_front (growing past capacity 2), then pop_front gives them back newest first
  mut d := deque::deque(u8, ptr(ar), 2)
  mut i : u64 = 0
  while i < 20 {
    p := deque::push_front(u8, d, u8(150 + i))
    i += 1
  }
  i = 0
  while i < 20 {
    o := deque::pop_front(u8, d)
    match o {
      Option::Some(x) => { if u64(x) != 169 - i { return 10 } }
      Option::None => { return 11 }
    }
    i += 1
  }

  ## i16, negative: push_front, then pop_back gives them back oldest first (sign extension)
  mut e := deque::deque(i16, ptr(ar), 2)
  i = 0
  while i < 20 {
    q := deque::push_front(i16, e, i16(i) - 300)
    i += 1
  }
  i = 0
  while i < 20 {
    oe := deque::pop_back(i16, e)
    match oe {
      Option::Some(x) => { if x != i16(i) - 300 { return 12 } }
      Option::None => { return 13 }
    }
    i += 1
  }

  ## u32 with every byte set: push_front, then pop_front
  mut f := deque::deque(u32, ptr(ar), 2)
  i = 0
  while i < 12 {
    s := deque::push_front(u32, f, u32(4042322160 + i))
    i += 1
  }
  i = 0
  while i < 12 {
    of := deque::pop_front(u32, f)
    match of {
      Option::Some(x) => { if u64(x) != 4042322171 - i { return 14 } }
      Option::None => { return 15 }
    }
    i += 1
  }

  ## bool: alternating push_front, then pop_back
  mut g := deque::deque(bool, ptr(ar), 2)
  i = 0
  while i < 10 {
    t := deque::push_front(bool, g, i % 2 == 0)
    i += 1
  }
  i = 0
  while i < 10 {
    og := deque::pop_back(bool, g)
    match og {
      Option::Some(x) => { if x != (i % 2 == 0) { return 16 } }
      Option::None => { return 17 }
    }
    i += 1
  }
  42
}
## expect: run 42
