## e2e (std::channel — non-blocking try_send / try_recv, Concurrency CC-4 path 1). Single-threaded
## poke at a capacity-1 `Channel(u64)`: `try_send(41)` must succeed (ring empty), a second `try_send`
## must FAIL (ring full, cap 1); then `try_recv` must yield `Some(41)`, and a second `try_recv` must
## yield `None` (ring drained). Confirms the non-blocking paths report room/emptiness without blocking
## and that the single stored value round-trips. Every check must hold → return 42.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut ch := std::channel::channel(u64, ptr(ar), 1)
  ok0 := std::channel::try_send(u64, ptr(ch), 41)
  ok1 := std::channel::try_send(u64, ptr(ch), 99)
  if ok0 == false { return 1 }
  if ok1 { return 2 }
  o0 := std::channel::try_recv(u64, ptr(ch))
  o1 := std::channel::try_recv(u64, ptr(ch))
  mut a : u64 = 0
  match o0 { Option::Some(v) => { a = v } Option::None => { return 3 } }
  match o1 { Option::Some(v) => { return 4 } Option::None => {} }
  if a == 41 { return 42 }
  return 5
}
