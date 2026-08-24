## e2e — `alloc::fmt::display` rendering a TUPLE `(a, b, …)`. A tuple type-arg `(u64, u64)` flows
## through the mono machinery (source-span captured + mangled to a paren-free tag), `typeinfo(T)`
## reports the `Tuple` kind, and the `Tuple` arm unrolls `comptime for c in typeinfo(T).components`,
## rendering `(3, 4)` — `v.(c)` projecting each component as `Index(v, i)`. Byte-for-byte check.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut sb := alloc::strbuf::strbuf(ptr(ar), 64)
  t : (u64, u64) = (3, 4)
  dr := alloc::fmt::display((u64, u64), t, sb)
  alloc::fmt::trap_oom(dr)
  ## expected: "(3, 4)" — 6 bytes.
  want := "(3, 4)"
  wb := bytes(want)
  buf : Slice(u8) = Slice(u8)(ptr = alloc::strbuf::strbuf_base(ptr(sb)), len = sb.len)
  mut ok : bool = true
  if sb.len != 6 { ok = false }
  mut i : usize = 0
  while i < 6 {
    if buf[i] != wb[i] { ok = false }
    i += 1
  }
  if ok { return 42 }
  1
}
