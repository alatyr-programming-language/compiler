## fmt round-trip for MODULE-DIRECTIVE decls (ROADMAP §5): import aliases (`name := path`, incl.
## `pub`) and a bodyless `@abi(syscall)` trampoline declaration. Before this, fmt fail-loud panicked
## ("unsupported declaration kind") on both — an alias is kind-0 with its path in ret_ts/ret_tl (which
## the value arm excludes via `ret_tl == 0`), and a syscall-ABI fn is kind 4 (no dispatch arm at all).
io := std::io
pub sb := alloc::strbuf
wr := @abi(syscall) fn(num : usize, fd : usize, buf : usize, len : usize) -> isize
main := fn() -> u64 {
  return 40 + 2
}
