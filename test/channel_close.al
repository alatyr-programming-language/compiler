## e2e (std::channel — close / EOF wakes a blocked receiver, Concurrency CC-4 path 1). main creates a
## capacity-2 `Channel(u64)` in an mmap'd arena and spawns ONE consumer thread that loops `recv_opt`
## (the blocking-with-EOF end), folding each `Some(v)` into a shared SUM and stopping on `None`. The
## consumer is spawned FIRST, so it blocks on the empty ring; main then `send`s 40 and 2 (waking it via
## the not-empty futex) and `close`s the channel. `close` must wake the consumer once it has drained
## both values and re-blocked on the now-empty ring, so its final `recv_opt` returns `None` (EOF) and
## the thread exits — no deadlock. SUM = 40 + 2 = 42 → return 42. A missed close-wakeup would hang the
## join (the e2e harness has no timeout, so a deadlock shows as a hang, not a wrong answer).
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

mut SUM : u64 = 0

consumer := fn(arg : usize) {
  chp := unchecked bitcast(ptr(mut std::channel::Channel(u64)), arg)
  mut done := false
  while done == false {
    o := std::channel::recv_opt(u64, chp)
    match o {
      Option::Some(v) => { SUM = SUM + v }
      Option::None => { done = true }
    }
  }
}

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut ch := std::channel::channel(u64, ptr(ar), 2)
  chp := unchecked bitcast(usize, ptr(ch))
  t := std::thread::spawn(unchecked bitcast(usize, consumer), chp)
  std::channel::send(u64, ptr(ch), 40)
  std::channel::send(u64, ptr(ch), 2)
  std::channel::close(u64, ptr(ch))
  std::thread::join(t)
  total := atomic::load(ptr(SUM), Ordering.acquire)
  if total == 42 { return 42 }
  return 1
}
