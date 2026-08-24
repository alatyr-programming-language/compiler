sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  base := bitcast(usize, r)
  deref(unchecked bitcast(ptr(mut u64), base)) = 1000
  deref(unchecked bitcast(ptr(mut u64), base + 8)) = 42        ## neighbour word
  deref(unchecked bitcast(ptr(mut u8), base + 1)) = 7          ## a SINGLE byte write
  w1 := deref(unchecked bitcast(ptr(mut u64), base + 8))       ## must stay 42
  b1 := deref(unchecked bitcast(ptr(mut u8), base + 1))        ## must read back 7 (1-byte load)
  if w1 != 42 { return 1 }
  if b1 != 7 { return 2 }
  ## signedness of a sub-word LOAD: 0xFF read through ptr(u8) is 255 (zero-extend); through
  ## ptr(i8) is -1 (sign-extend). Getting either wrong is a silent miscompile.
  deref(unchecked bitcast(ptr(mut u8), base + 2)) = 255
  bu : u8 = deref(unchecked bitcast(ptr(u8), base + 2))        ## zero-extend -> 255
  bs : i8 = deref(unchecked bitcast(ptr(i8), base + 2))        ## sign-extend  -> -1
  if u64(bu) != 255 { return 3 }
  if i64(bs) != 0 - 1 { return 4 }
  return 42
}
