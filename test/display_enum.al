## e2e — `alloc::fmt::display` ENUM rendering (the AMBIENT stdlib renderer, D87 / Stdlib §2.7;
## comptime variant match D90 / Comptime §5.5). Renders BOTH a payload variant `Just(5)` and a
## unit variant `Nothing` of the same enum into one StrBuf and checks the produced text BYTE FOR
## BYTE against `Just(5)Nothing`. Exercises: the `Enum(_)` arm's `comptime for var in
## typeinfo(T).variants` unroll, `var.name` (the variant's comptime `str`), the per-variant
## `comptime match var.payload` fold (`Some(_)` → recurse `display(p)`, `None` → name only), and
## the recursive scalar-leaf render of the `u64` payload. Returns 42 when the bytes match exactly.
## Raw syscall mmap so the test is self-contained (like `display_render`/`map_container`).
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

Opt := enum { Nothing, Just(u64) }

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut sb := alloc::strbuf::strbuf(ptr(ar), 64)
  d1 := alloc::fmt::display(Opt, Opt.Just(5), sb)
  alloc::fmt::trap_oom(d1)
  d2 := alloc::fmt::display(Opt, Opt.Nothing, sb)
  alloc::fmt::trap_oom(d2)
  ## expected: "Just(5)Nothing" — 14 bytes.
  want := "Just(5)Nothing"
  wb := bytes(want)
  buf : Slice(u8) = Slice(u8)(ptr = alloc::strbuf::strbuf_base(ptr(sb)), len = sb.len)
  mut ok : bool = true
  if sb.len != 14 { ok = false }
  mut i : usize = 0
  while i < 14 {
    if buf[i] != wb[i] { ok = false }
    i += 1
  }
  if ok { return 42 }
  1
}
