## e2e — `alloc::fmt::display` over a GENERIC ENUM INSTANCE (`Option(u64)`), the Option/Result
## display case (Stdlib §2.7, D87; comptime variant match D90). A generic-enum type argument
## parses as a `Call("Option", [u64])`; the lower extracts the bare head `Option` (gated on it
## naming an enum), positioned in source right before its `(u64)` — so `variant_payload_type` /
## `typearg_at` re-read the concrete `V = u64` from source (the generic-instance payload
## substitution already built for the enum-return path), the recursive `display(p, sb)` renders the
## `u64` payload, and the mangled label folds the type-args in (`display__Option_u64`) so distinct
## instantiations don't collide. Renders `Some(5)` (payloaded) then `None` (unit) of `Option(u64)`
## into one StrBuf and checks the bytes against `Some(5)None`. Returns 42 on an exact match.
## Raw syscall mmap so the test is self-contained (like `display_enum`/`map_container`).
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut sb := alloc::strbuf::strbuf(ptr(ar), 64)
  o : Option(u64) = Option(u64).Some(5)
  d1 := alloc::fmt::display(Option(u64), o, sb)
  alloc::fmt::trap_oom(d1)
  n : Option(u64) = Option(u64).None
  d2 := alloc::fmt::display(Option(u64), n, sb)
  alloc::fmt::trap_oom(d2)
  ## expected: "Some(5)None" — 11 bytes.
  want := "Some(5)None"
  wb := bytes(want)
  buf : Slice(u8) = Slice(u8)(ptr = alloc::strbuf::strbuf_base(ptr(sb)), len = sb.len)
  mut ok : bool = true
  if sb.len != 11 { ok = false }
  mut i : usize = 0
  while i < 11 {
    if buf[i] != wb[i] { ok = false }
    i += 1
  }
  if ok { return 42 }
  1
}
