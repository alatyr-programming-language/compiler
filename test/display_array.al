## e2e — `alloc::fmt::display` rendering a fixed ARRAY `[T; N]` as `[e0, e1, …]`. The array type-arg
## `[u64; 3]` flows through the mono machinery (source-span captured + mangled to `Array_u64_3`),
## `typeinfo(T)` reports the `Array` kind, and the `Array` arm unrolls `comptime for e in
## typeinfo(T).elements` (N steps), rendering each element via `v.(e)` — reusing the tuple
## component machinery. Byte-for-byte check against "[1, 2, 3]" (9 bytes). Returns 42 on match.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut sb := alloc::strbuf::strbuf(ptr(ar), 64)
  a : [u64; 3] = [1, 2, 3]
  dr := alloc::fmt::display([u64; 3], a, sb)
  alloc::fmt::trap_oom(dr)
  want := "[1, 2, 3]"
  wb := bytes(want)
  buf : Slice(u8) = Slice(u8)(ptr = alloc::strbuf::strbuf_base(ptr(sb)), len = sb.len)
  mut ok : bool = true
  if sb.len != 9 { ok = false }
  mut i : usize = 0
  while i < 9 {
    if buf[i] != wb[i] { ok = false }
    i += 1
  }
  if ok { return 42 }
  1
}
