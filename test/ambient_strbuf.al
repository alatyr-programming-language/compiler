## e2e — the allocator-borne `alloc::strbuf` container end to end through the AMBIENT path (no Rust
## seed): `strbuf(ptr(ar), cap)` builds a StrBuf over a raw `mmap` arena, then `push_str` (a `str`
## argument) and `push_byte` (both `in out StrBuf` mutators, called directly — the copyback lands)
## grow it; the final `.len` field read confirms the growth. "hello" (5) + 37 bytes = 42. Guards the
## ambient `in out` aggregate-mutator path + a `str`-taking stdlib call reached ambiently. Uses a raw
## `@abi(syscall)` mmap (no `std::os`) so the test is self-contained, like `map_container`.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut sb := alloc::strbuf::strbuf(ptr(ar), 128)
  alloc::strbuf::push_str(sb, "hello").expect("push_str")
  mut i : u64 = 0
  while i < 37 {
    alloc::strbuf::push_byte(sb, 88).expect("push_byte")
    i = i + 1
  }
  return sb.len
}
