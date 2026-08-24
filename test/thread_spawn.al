## e2e (std::thread — OS thread spawn + join over raw `clone`, Concurrency CC-1). Spawn one
## thread that atomically stores 42 into a shared module global, join it (futex-wait the thread
## out), then read the global back. The child shares the address space (CLONE_VM) so the global
## `SHARED` is the SAME cell in both threads. A correct spawn/join → 42.
mut SHARED := 0

worker := fn(arg : usize) {
  p := ptr(SHARED)
  atomic::store(p, 42, Ordering.seq_cst)
}

main := fn() -> u64 {
  t := std::thread::spawn(unchecked bitcast(usize, worker), 0)
  std::thread::join(t)
  p := ptr(SHARED)
  atomic::load(p, Ordering.acquire)
}
