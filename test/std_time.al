## e2e — std::time (clock_gettime). Deterministic checks (no wall-clock value assertion): two MONOTONIC
## reads are non-decreasing (diff_nanos >= 0), a REALTIME read is after the Unix epoch (to_nanos > 0 and
## to_millis > 0), and the pure `to_nanos` conversion is exact on a constructed Timespec. Returns 42 iff
## all hold. Raw `@abi(syscall)` mmap arena so it is self-contained.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
tm := std::time

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)

  t1 := tm::now_monotonic(ptr(ar))
  t2 := tm::now_monotonic(ptr(ar))
  d := tm::diff_nanos(t2, t1)              ## >= 0 (monotonic never goes backward)

  rt := tm::now_realtime(ptr(ar))
  rn := tm::to_nanos(rt)                    ## > 0 (after the epoch)
  rm := tm::to_millis(rt)                   ## > 0

  probe : tm::Timespec = tm::Timespec(sec = 2, nsec = 500000000)
  pn := tm::to_nanos(probe)                 ## 2*1e9 + 5e8 = 2_500_000_000

  if d >= 0 and rn > 0 and rm > 0 and pn == 2500000000 { return 42 }
  return 7
}
