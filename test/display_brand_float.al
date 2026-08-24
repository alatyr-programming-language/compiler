## e2e — `alloc::fmt::display` on a FLOAT-underlying user brand (`F := brand(f64)`, D9/D24/D25).
## The `Brand(under, _)` arm dispatches on the underlying `f64`'s kind (`Float`), so the value peels
## via `f64(v)` and renders through the float formatter (`F(3.5)` → "3.5"). Confirms the float-brand
## slot is tagged `ek == 9` (`type_is_float` in `bind_param`) so the peel is a reinterpret, not a
## `cvtsi2sd` int→float conversion of the raw IEEE bits. Returns 42 on an exact byte match.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

F := brand(f64)

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut sb := alloc::strbuf::strbuf(ptr(ar), 64)
  k : F = F(3.5)
  dr := alloc::fmt::display(F, k, sb)
  alloc::fmt::trap_oom(dr)
  ## expected: "3.5" — 3 bytes.
  want := "3.5"
  wb := bytes(want)
  buf : Slice(u8) = Slice(u8)(ptr = alloc::strbuf::strbuf_base(ptr(sb)), len = sb.len)
  mut ok : bool = true
  if sb.len != 3 { ok = false }
  mut i : usize = 0
  while i < 3 {
    if buf[i] != wb[i] { ok = false }
    i += 1
  }
  if ok { return 42 }
  1
}
