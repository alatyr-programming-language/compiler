## e2e — `alloc::fmt::display` over TWO distinct generic-enum instances in one program: `Option(u64)`
## (1 type-arg) AND `Result(u64, u64)` (2 type-args). Exercises the generic-instance display path for
## a MULTI-type-arg enum AND the per-instantiation label distinctness (`add_inst`'s `inst_targ_eq`
## keeps `display__Option_u64` and `display__Result_u64_u64` as separate instances — a plain head
## dedup would collide two same-base instantiations). Renders `Some(5)` then `Ok(7)` and checks the
## bytes against `Some(5)Ok(7)`. Returns 42 on an exact match. Self-contained raw-syscall mmap.
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
  rr : Result(u64, u64) = Result(u64, u64).Ok(7)
  d2 := alloc::fmt::display(Result(u64, u64), rr, sb)
  alloc::fmt::trap_oom(d2)
  ## expected: "Some(5)Ok(7)" — 12 bytes.
  want := "Some(5)Ok(7)"
  wb := bytes(want)
  buf : Slice(u8) = Slice(u8)(ptr = alloc::strbuf::strbuf_base(ptr(sb)), len = sb.len)
  mut ok : bool = true
  if sb.len != 12 { ok = false }
  mut i : usize = 0
  while i < 12 {
    if buf[i] != wb[i] { ok = false }
    i += 1
  }
  if ok { return 42 }
  1
}
