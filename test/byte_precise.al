## TOOL-5 / backend regression: byte-element Slice writes and pointer dereferences must not widen to a
## word store. Sentinel bytes on both sides of each target make a wide `movq` immediately observable.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

write_slice := fn(in out dst : Slice(u8)) {
  dst[1] = 101
  dst[2] = 102
}

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut u8), bitcast(usize, r))
  p0 := unchecked bitcast(ptr(mut bits8), bitcast(usize, bp))
  p1 := unchecked bitcast(ptr(mut bits8), bitcast(usize, bp) + 1)
  p2 := unchecked bitcast(ptr(mut bits8), bitcast(usize, bp) + 2)
  p3 := unchecked bitcast(ptr(mut bits8), bitcast(usize, bp) + 3)
  deref(p0) = 17
  deref(p1) = 18
  deref(p2) = 19
  deref(p3) = 20
  dst := Slice(u8)(ptr = bp, len = 4)
  write_slice(dst)
  if deref(p0) != 17 { return 1 }
  if deref(p1) != 101 { return 2 }
  if deref(p2) != 102 { return 3 }
  if deref(p3) != 20 { return 4 }
  mut xs : [u8; 4] = [31, 32, 33, 34]
  view := xs[0..4]
  view[1] = 77
  if xs[0] != 31 { return 5 }
  if xs[1] != 77 { return 6 }
  if xs[2] != 33 { return 7 }
  if xs[3] != 34 { return 8 }
  42
}
