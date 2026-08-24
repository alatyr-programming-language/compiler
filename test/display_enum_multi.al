## e2e — `alloc::fmt::display` on a MULTI-COMPONENT enum payload. `E.Pair(3, 4)` binds its payload
## as a TUPLE `(u64, u64)`; the enum arm detects the tuple payload (`comptime match typeinfo(p)`)
## and renders it via the tuple machinery WITHOUT a redundant wrap — `Pair(3, 4)`, not `Pair((3, 4))`.
## Exercises: multi-word payload materialization + by-ref pass, the tuple type-arg span/mangling, and
## the payload-typeinfo fold. Byte-for-byte check against "Pair(3, 4)" (10 bytes). Returns 42 on match.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

E := enum { Pair(u64, u64), None }

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut sb := alloc::strbuf::strbuf(ptr(ar), 64)
  e := E.Pair(3, 4)
  dr := alloc::fmt::display(E, e, sb)
  alloc::fmt::trap_oom(dr)
  want := "Pair(3, 4)"
  wb := bytes(want)
  buf : Slice(u8) = Slice(u8)(ptr = alloc::strbuf::strbuf_base(ptr(sb)), len = sb.len)
  mut ok : bool = true
  if sb.len != 10 { ok = false }
  mut i : usize = 0
  while i < 10 {
    if buf[i] != wb[i] { ok = false }
    i += 1
  }
  if ok { return 42 }
  1
}
