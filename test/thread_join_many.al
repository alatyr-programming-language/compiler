## e2e (std::thread — join many; shared atomic counter under real contention). Spawn 3 threads,
## each atomically `fetch_add(1)` a shared module global 1000 times (3000 concurrent RMWs on one
## cell), join all three, then read the counter. The atomic RMW serializes the increments, so a
## correct spawn/join/atomic path yields exactly 3000 → return 42 (a plain `+` would tear/lose
## updates and miss 3000).
mut CTR := 0

worker := fn(arg : usize) {
  p := ptr(CTR)
  mut i := 0
  while i < 1000 {
    r := atomic::fetch_add(p, 1, Ordering.seq_cst)
    i = i + 1
  }
}

main := fn() -> u64 {
  fp := unchecked bitcast(usize, worker)
  t0 := std::thread::spawn(fp, 0)
  t1 := std::thread::spawn(fp, 0)
  t2 := std::thread::spawn(fp, 0)
  std::thread::join(t0)
  std::thread::join(t1)
  std::thread::join(t2)
  p := ptr(CTR)
  c := atomic::load(p, Ordering.acquire)
  if c == 3000 { return 42 }
  return 1
}
