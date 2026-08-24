## e2e — `display` over a NESTED aggregate with mixed scalar leaves (the `Scalar` numeric-kind
## dispatch + the aggregate-field-through-pointer recursion). `Wrap { c : char, inner : Leaf, f :
## f64 }` where `Leaf { n : u64 }` renders as `{ c = A, inner = { n = 7 }, f = 2.5 }` — exercising a
## `char` leaf ('A'=65), a NESTED struct field (passed BY REFERENCE, recursed into), and an `f64`
## leaf (the generic float-param ABI + decimal formatter). Byte-compares the rendered buffer against
## the expected text and returns 42 on an exact match. Raw `mmap` arena, self-contained.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

Leaf := struct { n : u64 }
Wrap := struct { c : char, inner : Leaf, f : f64 }

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut sb := alloc::strbuf::strbuf(ptr(ar), 128)
  w := Wrap(c = 'A', inner = Leaf(n = 7), f = 2.5)
  dr := alloc::fmt::display(Wrap, w, sb)
  alloc::fmt::trap_oom(dr)
  want := "{ c = A, inner = { n = 7 }, f = 2.5 }"
  wb := bytes(want)
  buf : Slice(u8) = Slice(u8)(ptr = alloc::strbuf::strbuf_base(ptr(sb)), len = sb.len)
  mut ok : bool = true
  if sb.len != 37 { ok = false }
  mut i : usize = 0
  while i < sb.len {
    if buf[i] != wb[i] { ok = false }
    i += 1
  }
  if ok { return 42 }
  1
}
