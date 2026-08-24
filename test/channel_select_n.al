## e2e (std::channel — v1 `select_recv` over N channels, Concurrency CC-4 path 1). main builds THREE
## capacity-4 `Channel(u64)`s in an mmap'd arena and spawns THREE producer threads (the SAME `producer`
## fn, one per channel): each sends 1..=4 (sum 10) then `close`s its channel. The main thread is the
## CONSUMER: it builds a `[ptr(mut Channel(u64)); 3]` of the three channel pointers, takes a SLICE of it,
## and loops `select_recv(chans)`, folding each `some` value into a running sum, stopping when the select
## reports `some == false` — the all-inputs-EOF marker (every channel closed AND drained). A correct
## N-way select drains ALL THREE channels (never reporting EOF while any still has data or is open) and
## terminates once all are done, so the sum is 10 + 10 + 10 + 12 = 42 → return 42. (The three channels
## contribute 30; a fourth channel carrying a single 12 makes the total 42, exercising a heterogeneous
## slice of length 4.) A select that busy-spun forever or missed the EOF would hang the thread joins.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

producer := fn(arg : usize) {
  chp := unchecked bitcast(ptr(mut std::channel::Channel(u64)), arg)
  mut i : u64 = 1
  while i <= 4 {
    std::channel::send(u64, chp, i)
    i = i + 1
  }
  std::channel::close(u64, chp)
}

producer12 := fn(arg : usize) {
  chp := unchecked bitcast(ptr(mut std::channel::Channel(u64)), arg)
  std::channel::send(u64, chp, 12)
  std::channel::close(u64, chp)
}

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut cha := std::channel::channel(u64, ptr(ar), 4)
  mut chb := std::channel::channel(u64, ptr(ar), 4)
  mut chc := std::channel::channel(u64, ptr(ar), 4)
  mut chd := std::channel::channel(u64, ptr(ar), 4)
  ap := unchecked bitcast(usize, ptr(cha))
  bpp := unchecked bitcast(usize, ptr(chb))
  cpp := unchecked bitcast(usize, ptr(chc))
  dpp := unchecked bitcast(usize, ptr(chd))
  pf := unchecked bitcast(usize, producer)
  pf12 := unchecked bitcast(usize, producer12)
  ta := std::thread::spawn(pf, ap)
  tb := std::thread::spawn(pf, bpp)
  tc := std::thread::spawn(pf, cpp)
  td := std::thread::spawn(pf12, dpp)
  chans : [ptr(mut std::channel::Channel(u64)); 4] = [ptr(cha), ptr(chb), ptr(chc), ptr(chd)]
  mut sum : u64 = 0
  mut done := false
  while done == false {
    sr := std::channel::select_recv(u64, chans[0..4])
    if sr.some {
      sum = sum + sr.value
    } else {
      done = true
    }
  }
  std::thread::join(ta)
  std::thread::join(tb)
  std::thread::join(tc)
  std::thread::join(td)
  if sum == 42 { return 42 }
  return 1
}
