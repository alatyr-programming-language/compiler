## e2e — `alloc::fmt::display` on an ARRAY of STRUCTS `[Pt; 2]`: each element is passed BY REFERENCE
## (its address within the array, `-(i*elemwords*8)(ptr)`, uniform stride) so the renderer recurses
## into it, rather than reading its first word as a scalar (which segfaulted). Byte-checks
## "[{ x = 1, y = 2 }, { x = 3, y = 4 }]" (36 bytes). Returns 42 on match.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

Pt := struct { x : u64, y : u64 }

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut sb := alloc::strbuf::strbuf(ptr(ar), 64)
  a : [Pt; 2] = [Pt(x = 1, y = 2), Pt(x = 3, y = 4)]
  dr := alloc::fmt::display([Pt; 2], a, sb)
  alloc::fmt::trap_oom(dr)
  want := "[{ x = 1, y = 2 }, { x = 3, y = 4 }]"
  wb := bytes(want)
  buf : Slice(u8) = Slice(u8)(ptr = alloc::strbuf::strbuf_base(ptr(sb)), len = sb.len)
  mut ok : bool = true
  if sb.len != 36 { ok = false }
  mut i : usize = 0
  while i < 36 {
    if buf[i] != wb[i] { ok = false }
    i += 1
  }
  if ok { return 42 }
  1
}
