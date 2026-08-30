## e2e/fmt — a return type with two namespace hops must survive formatting, together with the
## function body that follows its signature. The trailing declaration makes truncation observable.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

make_buffer := fn(a : ptr(mut Arena)) -> alloc::strbuf::StrBuf {
  return alloc::strbuf::strbuf(a, 64)
}

tail := fn() -> u64 {
  return 40
}

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut sb := make_buffer(ptr(ar))
  return tail() + 2
}
