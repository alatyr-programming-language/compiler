## e2e — a TUPLE LITERAL passed DIRECTLY as a by-value argument (not via a local). `display((u64,
## u64, u64), (10, 20, 30), sb)` must materialize the literal into the aggregate-temp block and pass
## its address by reference (the tuple dual of a struct-ctor arg); previously a tuple literal fell to
## the scalar arg default and pushed garbage (segfault / no output). A tuple LOCAL already worked.
## Byte-for-byte check against "(10, 20, 30)" (12 bytes). Returns 42 on match.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut sb := alloc::strbuf::strbuf(ptr(ar), 64)
  dr := alloc::fmt::display((u64, u64, u64), (10, 20, 30), sb)
  alloc::fmt::trap_oom(dr)
  want := "(10, 20, 30)"
  wb := bytes(want)
  buf : Slice(u8) = Slice(u8)(ptr = alloc::strbuf::strbuf_base(ptr(sb)), len = sb.len)
  mut ok : bool = true
  if sb.len != 12 { ok = false }
  mut i : usize = 0
  while i < 12 {
    if buf[i] != wb[i] { ok = false }
    i += 1
  }
  if ok { return 42 }
  1
}
