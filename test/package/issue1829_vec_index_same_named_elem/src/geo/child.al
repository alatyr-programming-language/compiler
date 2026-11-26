## The bare `Node` here is `geo`'s, the nearest declaration up the chain: not the root's (`b` at
## offset 0, would read 99) and not the sibling `m`'s (`b` at offset 8, would read 3).
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

pub run := fn() -> u64 {
  r := unchecked sys_mmap(std::sysno::MMAP, 0, 65536, 3, 34, bitcast(usize, 0 - 1), 0)
  mut ar := arena_over(unchecked bitcast(ptr(mut bits8), bitcast(usize, r)), 65536)
  mut v := alloc::vec::new(Node, ptr(ar))
  p0 := v.push(Node(z = 99, y = 3, b = 14))
  return v.at(0).b
}
## Compiled alone (the corpus walk), this file names a type `Node` it does not declare.
## expect: reject
