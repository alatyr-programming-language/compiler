## e2e (std::channel — SPSC bounded channel, Concurrency CC-4 path 1). main creates a capacity-4
## `Channel(u64)` in an mmap'd arena, spawns ONE producer thread that `send`s 1..=1000 down it, and
## itself `recv`s 1000 values and sums them. The small ring (cap 4 << 1000) forces the futex
## full/empty blocking handshake many times over. A correct channel delivers every value exactly
## once in order → sum = 1000*1001/2 = 500500 → return 42. A lost/torn/duplicated message misses it.
## The channel lives as a `main` stack local; its address is handed to the producer as the thread arg
## (the `CLONE_VM` child shares main's address space, and main joins before returning, so the local
## stays live), and the ring pages live in the shared mmap arena.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

producer := fn(arg : usize) {
  chp := unchecked bitcast(ptr(mut std::channel::Channel(u64)), arg)
  mut i : u64 = 1
  while i <= 1000 {
    std::channel::send(u64, chp, i)
    i = i + 1
  }
}

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut ch := std::channel::channel(u64, ptr(ar), 4)
  chp := unchecked bitcast(usize, ptr(ch))
  t := std::thread::spawn(unchecked bitcast(usize, producer), chp)
  mut sum : u64 = 0
  mut i : u64 = 0
  while i < 1000 {
    v := std::channel::recv(u64, ptr(ch))
    sum = sum + v
    i = i + 1
  }
  std::thread::join(t)
  if sum == 500500 { return 42 }
  return 1
}
