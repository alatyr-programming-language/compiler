## e2e — `alloc::fmt::display` recursing into AGGREGATE FIELDS of a struct: an ARRAY field `[u64; 2]`
## and a TUPLE field `(u64, u64)`. Such a field is passed BY REFERENCE (its word-0 address) so the
## renderer recurses into it (`display([u64;2], &v.v)` / `display((u64,u64), &s.t)`), rather than
## reading only its first word as a scalar. Exercises: the parser capturing the full `[T; N]` /
## `(…)` field type span + sizing the field by its word count; the by-ref aggregate-field arg;
## instance collection of the field's array/tuple display. Byte-checks "{ v = [1, 2], t = (3, 4),
## z = 9 }" (33 bytes). Returns 42 on match.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

S := struct { v : [u64; 2], t : (u64, u64), z : u64 }

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut sb := alloc::strbuf::strbuf(ptr(ar), 64)
  s := S(v = [1, 2], t = (3, 4), z = 9)
  dr := alloc::fmt::display(S, s, sb)
  alloc::fmt::trap_oom(dr)
  want := "{ v = [1, 2], t = (3, 4), z = 9 }"
  wb := bytes(want)
  buf : Slice(u8) = Slice(u8)(ptr = alloc::strbuf::strbuf_base(ptr(sb)), len = sb.len)
  mut ok : bool = true
  if sb.len != 33 { ok = false }
  mut i : usize = 0
  while i < 33 {
    if buf[i] != wb[i] { ok = false }
    i += 1
  }
  if ok { return 42 }
  1
}
