## The root's own `Node`: `b` first. The element type of `v` is spelled here, so it is this one.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
Node := struct { b : u64, c : u64, a : u64 }

main := fn() -> u64 {
  r := unchecked sys_mmap(std::sysno::MMAP, 0, 65536, 3, 34, bitcast(usize, 0 - 1), 0)
  mut ar := arena_over(unchecked bitcast(ptr(mut bits8), bitcast(usize, r)), 65536)
  mut v := alloc::vec::new(Node, ptr(ar))
  p0 := v.push(Node(b = 20, c = 7, a = 5))
  p1 := v.push(Node(b = 8, c = 8, a = 6))
  return v[1].b + v[0].b + geo::child::run() + m::zero()
}
## Compiled alone (the corpus walk), this file names modules `geo` and `m` it does not have.
## expect: reject
