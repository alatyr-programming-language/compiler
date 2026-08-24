## e2e — the `alloc::string` container end to end through the AMBIENT path (no Rust seed). String is
## a thin layer over `strbuf::StrBuf`, referenced by a BARE module name (`strbuf::`, NO tier prefix),
## so this exercises BARE-module ambient injection: the scanner, seeing `alloc::string::`, injects
## `lib/alloc/string.al`, then — scanning THAT injected lib file — resolves its bare `strbuf::StrBuf`
## / `strbuf::strbuf(…)` refs to `lib/alloc/strbuf.al` and injects it too. `string(…)` + `push_str`
## grow it; `.len` confirms. "hi" (2) + 40 = 42. Raw `@abi(syscall)` mmap so it is self-contained.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut s := alloc::string::string(ptr(ar), 128)
  alloc::string::push_str(s, "hi").expect("push_str")
  mut i : u64 = 0
  while i < 40 {
    alloc::string::push_str(s, "x").expect("push_str")
    i = i + 1
  }
  return s.len
}
