## e2e — `alloc::fmt::display` on a TUPLE with an aggregate component `(Pt, u64)`. The struct
## component is passed BY REFERENCE at its cumulative word offset (0) and renders `{ x = 1, y = 2 }`;
## the trailing scalar sits at the cumulative offset PAST the struct (word 2, not the raw index 1),
## rendering `9` — via `cf_member_woff`. Byte-checks "({ x = 1, y = 2 }, 9)" (21 bytes). Returns 42.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

Pt := struct { x : u64, y : u64 }

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut sb := alloc::strbuf::strbuf(ptr(ar), 64)
  t : (Pt, u64) = (Pt(x = 1, y = 2), 9)
  dr := alloc::fmt::display((Pt, u64), t, sb)
  alloc::fmt::trap_oom(dr)
  want := "({ x = 1, y = 2 }, 9)"
  wb := bytes(want)
  buf : Slice(u8) = Slice(u8)(ptr = alloc::strbuf::strbuf_base(ptr(sb)), len = sb.len)
  mut ok : bool = true
  if sb.len != 21 { ok = false }
  mut i : usize = 0
  while i < 21 {
    if buf[i] != wb[i] { ok = false }
    i += 1
  }
  if ok { return 42 }
  1
}
