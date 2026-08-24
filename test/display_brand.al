## e2e — `alloc::fmt::display` on a USER NOMINAL BRAND (D9/D24/D25). `Id := brand(u64)` is a
## compile-time nominal wrapper over `u64` with `u64`'s exact runtime representation. `display`'s
## `Brand(under, _)` arm dispatches on the UNDERLYING type's kind (`typeinfo(under)`), so a brand
## over an unsigned integer renders as base-10 (`Id(7)` → "7"). Confirms: brand construction
## (`Id(7)` peels to `u64`), the `Brand` typeinfo kind, and the underlying-type rebind in the
## comptime-match folder. Returns 42 when the rendered bytes match exactly. Raw syscall mmap so the
## test is self-contained (like `display_render`).
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

Id := brand(u64)

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut sb := alloc::strbuf::strbuf(ptr(ar), 64)
  k : Id = Id(7)
  dr := alloc::fmt::display(Id, k, sb)
  alloc::fmt::trap_oom(dr)
  ## expected: "7" — 1 byte.
  want := "7"
  wb := bytes(want)
  buf : Slice(u8) = Slice(u8)(ptr = alloc::strbuf::strbuf_base(ptr(sb)), len = sb.len)
  mut ok : bool = true
  if sb.len != 1 { ok = false }
  mut i : usize = 0
  while i < 1 {
    if buf[i] != wb[i] { ok = false }
    i += 1
  }
  if ok { return 42 }
  1
}
