## e2e (std::channel — v1 `select2_recv` over TWO channels, Concurrency CC-4 path 1). main builds two
## capacity-4 `Channel(u64)`s in an mmap'd arena and spawns TWO producer threads (the SAME `producer`
## fn, one per channel): each sends 1..=6 (sum 21) then `close`s its channel. The main thread is the
## CONSUMER: it loops `select2_recv(ch_a, ch_b)`, folding each `some` value into a running sum, and
## stops when the select reports `some == false` — the all-inputs-EOF marker (both channels closed AND
## drained). A correct select drains BOTH channels (never reporting EOF while either still has data or
## is open) and terminates once both are done, so the sum is 21 + 21 = 42 → return 42. A select that
## busy-spun forever or missed the EOF would hang the join (the harness has no timeout → shows as a hang).
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

producer := fn(arg : usize) {
  chp := unchecked bitcast(ptr(mut std::channel::Channel(u64)), arg)
  mut i : u64 = 1
  while i <= 6 {
    std::channel::send(u64, chp, i)
    i = i + 1
  }
  std::channel::close(u64, chp)
}

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut cha := std::channel::channel(u64, ptr(ar), 4)
  mut chb := std::channel::channel(u64, ptr(ar), 4)
  ap := unchecked bitcast(usize, ptr(cha))
  bpp := unchecked bitcast(usize, ptr(chb))
  pf := unchecked bitcast(usize, producer)
  ta := std::thread::spawn(pf, ap)
  tb := std::thread::spawn(pf, bpp)
  mut sum : u64 = 0
  mut done := false
  while done == false {
    sr := std::channel::select2_recv(u64, ptr(cha), ptr(chb))
    if sr.some {
      sum = sum + sr.value
    } else {
      done = true
    }
  }
  std::thread::join(ta)
  std::thread::join(tb)
  if sum == 42 { return 42 }
  return 1
}
