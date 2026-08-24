## e2e — `alloc::fmt::display` structural rendering end to end (the AMBIENT stdlib renderer,
## Stdlib §2.7). Builds a StrBuf over a raw `mmap` arena, renders a flat struct of scalars via
## `display`, and checks the produced text BYTE FOR BYTE against the expected `{ x = 3, y = -7 }`
## (an unsigned `u64` field and a signed `i64` field — exercising the `Scalar` arm's numeric-kind
## dispatch AND the aggregate arm's `comptime for` over fields with `f.name` + `v.(f)` recursion).
## Confirms: field-name emission (`.Lfld`), the `push_str` byte copy, signed vs unsigned leaves, and
## the `{ name = value, … }` layout. Returns 42 when the rendered bytes match exactly. Raw syscall
## mmap so the test is self-contained (no `std::os`), like `map_container`/`ambient_strbuf`.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

Point := struct { x : u64, y : i64 }

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut sb := alloc::strbuf::strbuf(ptr(ar), 64)
  p := Point(x = 3, y = 0 - 7)
  dr := alloc::fmt::display(Point, p, sb)
  alloc::fmt::trap_oom(dr)
  ## expected: "{ x = 3, y = -7 }" — 17 bytes. Compare the rendered buffer BYTE FOR BYTE against
  ## `want` via `Slice(u8)` indexing (a byte load) on both — the buffer viewed as a `[u8]` over its
  ## backing, and `want`'s bytes.
  want := "{ x = 3, y = -7 }"
  wb := bytes(want)
  buf : Slice(u8) = Slice(u8)(ptr = alloc::strbuf::strbuf_base(ptr(sb)), len = sb.len)
  mut ok : bool = true
  if sb.len != 17 { ok = false }
  mut i : usize = 0
  while i < 17 {
    if buf[i] != wb[i] { ok = false }
    i += 1
  }
  if ok { return 42 }
  1
}
