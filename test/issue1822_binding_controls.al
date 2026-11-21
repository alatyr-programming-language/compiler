## #1822 positive controls for the call-binding check (Functions §2.3, §5.1, §5.5): an omitted `in`
## parameter with a default takes it, an allocator parameter omitted inside `alloc::with` takes the
## ambient (MEM-5), named arguments bind by name, and a forward callee with every parameter bound is
## accepted. (20 + 10) + (10 - 5) + 4 + 3 = 42.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
add := fn(a : u64, b : u64 = 10) -> u64 { a + b }
take := fn(ar : ptr(mut Arena), x : u64) -> u64 { x + 1 }
main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(std::sysno::MMAP, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut t : u64 = 0
  alloc::with(ar) {
    t = take(2)
  }
  mut s : u64 = 0
  later(4, s)
  add(20) + sub2(y = 5, x = 10) + s + t
}
sub2 := fn(x : u64, y : u64) -> u64 { x - y }
later := fn(k : u64, in out s : u64) { s = k }
## expect: run 42
