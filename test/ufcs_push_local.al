## e2e — UFCS `v.push(<local>)` monomorphizes when the pushed value is a fn-level LOCAL. The mono
## pre-pass types the generic call's local value arg via `block_decl_type` (params live in `penv`,
## locals do not), GATED on the callee taking a container/`ptr` RECEIVER as its first runtime param
## (so `hash(key)`-style by-value calls are untouched). Push two locals (30, 12) into an arena-backed
## Vec via UFCS, sum with a for-loop: 30 + 12 = 42.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut v := alloc::vec::with_capacity(u64, ptr(ar), 8)
  mut lo : u64 = 30
  mut hi : u64 = 12
  z0 := v.push(lo)
  z1 := v.push(hi)
  mut sum : u64 = 0
  unchecked {
    for x in v {
      sum = sum + x
    }
  }
  return sum
}
