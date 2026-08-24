## e2e — REGALLOC Vec-LOCAL: `for x in v` over an arena-backed `Vec(u64)` LOCAL in the register-allocated IR
## path. The Vec-build chain (mmap / arena_over / with_capacity / push) is text-spliced through GENERAL
## STATEMENT BARRIERS (the aggregate stays frame-resident — the HYBRID-BARRIER model); only the sum loop's
## scalar cursors are register-allocated. The loop hoists base = arena.base + idx and len ONCE into vregs,
## then loads each element `*(base + i*8)` through a register-held address — no per-iteration frame reload of
## base/len/index. The exit code must be IDENTICAL default (regalloc) vs `ALATYR_RA=0` (text). 10+20+12 = 42.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, 0 - 1), 0)
  mut ar := arena_over(unchecked bitcast(ptr(mut bits8), bitcast(usize, r)), 65536)
  mut v := alloc::vec::with_capacity(u64, ptr(ar), 16)
  p1 := alloc::vec::push(u64, v, 10)
  p2 := alloc::vec::push(u64, v, 20)
  p3 := alloc::vec::push(u64, v, 12)
  mut sum : u64 = 0
  unchecked {
    for x in v {
      sum = sum + x
    }
  }
  sum
}
