## e2e / issue #1334 — a store through a pointer to a niche-folded `Option(ptr(T))` writes ONE word.
##
## Memory §4: `Option(ptr(T))` lowers identically to a raw pointer-width value. `deref(p) = o` with `o`
## a folded local or parameter sized its source as an enum (`1 + payload words`) and wrote a second word
## over whatever followed the pointee. `deque::push_front` at `T = Option(ptr(u64))` stores below the
## previous front, so that element then read `None` (the container-matrix cell
## `deque.push_front.option_ptr`, #1302).
##
## Each check owns a code from 100 up; 42 means the neighbour word survived every store.
## Parent `1262da5d` (x86_64, omen): built rc 0 and returned 100 where 42 was due.
deque := alloc::deque
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

pkey := fn(o : Option(ptr(u64))) -> usize {
  match o {
    Option::Some(q) => { return unchecked bitcast(usize, q) }
    Option::None => { return 1 }
  }
}
put := fn(p : ptr(mut Option(ptr(u64))), o : Option(ptr(u64))) { deref(p) = o }

main := fn() -> u64 {
  r := unchecked sys_mmap(std::sysno::MMAP, 0, 1048576, 3, 34, bitcast(usize, 0 - 1), 0)
  mut ar := arena_over(unchecked bitcast(ptr(mut bits8), bitcast(usize, r)), 1048576)
  r2 := unchecked sys_mmap(std::sysno::MMAP, 0, 4096, 3, 34, bitcast(usize, 0 - 1), 0)
  base := unchecked bitcast(usize, r2)
  p := unchecked bitcast(ptr(mut Option(ptr(u64))), base)
  nb := unchecked bitcast(ptr(mut u64), base + 8)
  deref(nb) = 9
  o := Option(ptr(u64)).Some(unchecked bitcast(ptr(u64), base + 64))
  deref(p) = o
  if deref(nb) != 9 { return 100 }
  put(p, o)
  if deref(nb) != 9 { return 101 }

  ## the generic store `deref(slot) = x` at `T = Option(ptr(u64))`, below the previous front
  mut d := deque::deque(Option(ptr(u64)), ptr(ar), 16)
  f0 := deque::push_front(Option(ptr(u64)), d, Option(ptr(u64)).None)
  f1 := deque::push_front(Option(ptr(u64)), d, Option(ptr(u64)).Some(unchecked bitcast(ptr(u64), base + 16)))
  f2 := deque::push_front(Option(ptr(u64)), d, Option(ptr(u64)).Some(unchecked bitcast(ptr(u64), base + 24)))
  a1 := deque::dq_at(Option(ptr(u64)), ptr(d), 1)
  match a1 {
    Option::Some(x) => { if pkey(x) != base + 16 { return 102 } }
    Option::None => { return 103 }
  }
  42
}
