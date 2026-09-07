## Issue #524 over-reach control — `buf_push` (lib/base/alloc.al) belongs to the private `Buf(T)`
## growable-buffer helper set. The Stdlib appendix §5.1/§5.2.1 code blocks name `Mechanism`,
## `AllocError`, `mechanism`, `allocate`, `free`, `Handle`, `Arena`, `arena_over`, `get` and `close`
## and NOT `Buf`/`buf_*`, so Modules §3:90-92 keeps the whole `Buf` set out of the public API.
##
## Self-proving, and red on the parent for a DIFFERENT line: lines 16 and 18 use the §5.2.1 surface
## `base::alloc::arena_over` / `base::alloc::get`, which #524 publishes — on the parent the rejection
## lands on line 16 instead, so this row also measures the marker unit. After #524 the only refused
## line is 19.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := base::alloc::arena_over(bp, 65536)
  @alloc(ar) h := 40
  p := base::alloc::get(isize, ar, h)
  base::alloc::buf_push(u64, h, ar, 42)
  return u64(deref(p)) + 2
}
