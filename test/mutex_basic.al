## e2e (std::sync — contended futex Mutex(u64), Concurrency CC-4). Two threads each acquire the
## shared Mutex and increment the guarded counter 50000 times (100000 lock/inc/unlock pairs racing
## on one cell). The mutex serializes the writers, so a correct lock/unlock (CAS fast path + futex
## contention path) yields exactly 100000 → return 42. Without real mutual exclusion the increments
## would tear and the total would fall short.
mut MTX := std::sync::new(u64, 0)

worker := fn(arg : usize) {
  mut i := 0
  while i < 50000 {
    p := std::sync::lock(u64, ptr(MTX))
    deref(p) = deref(p) + 1
    std::sync::unlock(u64, ptr(MTX))
    i = i + 1
  }
}

main := fn() -> u64 {
  fp := unchecked bitcast(usize, worker)
  t0 := std::thread::spawn(fp, 0)
  t1 := std::thread::spawn(fp, 0)
  std::thread::join(t0)
  std::thread::join(t1)
  p := std::sync::lock(u64, ptr(MTX))
  total := deref(p)
  std::sync::unlock(u64, ptr(MTX))
  if total == 100000 { return 42 }
  return 1
}
