## e2e (std::channel — MPMC bounded channel, Concurrency CC-4 path 1). A capacity-4 `Channel(u64)`
## with TWO producer threads (each `send`s 1..=500 → 1000 messages total, sum = 2*500*501/2 = 250500)
## and TWO consumer threads racing on both ends of the ring. Consumers coordinate with a shared atomic
## TICKETS counter so that EXACTLY 1000 `recv`s happen across the two of them (each claims a ticket;
## once tickets are exhausted a consumer stops instead of blocking on an empty ring forever) — so the
## consumer count matches the producer count and nothing deadlocks. Each consumer atomically folds the
## values it takes into a shared SUM. A correct MPMC channel delivers all 1000 messages exactly once →
## SUM = 250500 → return 42. The channel is a `main` local; its address is the shared thread arg.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

mut TICKETS : u64 = 0
mut SUM : u64 = 0

producer := fn(arg : usize) {
  chp := unchecked bitcast(ptr(mut std::channel::Channel(u64)), arg)
  mut i : u64 = 1
  while i <= 500 {
    std::channel::send(u64, chp, i)
    i = i + 1
  }
}

consumer := fn(arg : usize) {
  chp := unchecked bitcast(ptr(mut std::channel::Channel(u64)), arg)
  tp := ptr(TICKETS)
  sp := ptr(SUM)
  mut done := false
  while done == false {
    my := atomic::fetch_add(tp, 1, Ordering.seq_cst)
    if my >= 1000 {
      done = true
    } else {
      v := std::channel::recv(u64, chp)
      old := atomic::fetch_add(sp, v, Ordering.seq_cst)
    }
  }
}

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut ch := std::channel::channel(u64, ptr(ar), 4)
  chp := unchecked bitcast(usize, ptr(ch))
  pf := unchecked bitcast(usize, producer)
  cf := unchecked bitcast(usize, consumer)
  p0 := std::thread::spawn(pf, chp)
  p1 := std::thread::spawn(pf, chp)
  c0 := std::thread::spawn(cf, chp)
  c1 := std::thread::spawn(cf, chp)
  std::thread::join(p0)
  std::thread::join(p1)
  std::thread::join(c0)
  std::thread::join(c1)
  total := atomic::load(ptr(SUM), Ordering.acquire)
  if total == 250500 { return 42 }
  return 1
}
