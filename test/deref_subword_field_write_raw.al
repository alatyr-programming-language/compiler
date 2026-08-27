## Issue #167: raw-memory witness for exact width and after-object preservation.
## A standard P8 object occupies two bytes at an explicitly chosen address.  Bytes after it and a word
## at the next aligned address are sentinels.  Position 0 catches a wide store that destroys the
## neighbour/bytes after the object; position 1 catches the old word offset and its after-object write.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
P8 := struct { a : u8, b : u8 }

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  base := bitcast(usize, r) + 128
  deref(unchecked bitcast(ptr(mut u8), base)) = 3
  deref(unchecked bitcast(ptr(mut u8), base + 1)) = 11
  deref(unchecked bitcast(ptr(mut u8), base + 2)) = 17
  deref(unchecked bitcast(ptr(mut u64), base + 8)) = 100

  p := unchecked bitcast(ptr(mut P8), base)
  deref(p).a = 8
  if deref(unchecked bitcast(ptr(u8), base + 1)) != 11 { return 1 }
  if deref(unchecked bitcast(ptr(u8), base + 2)) != 17 { return 2 }

  deref(p).b = 13
  if deref(unchecked bitcast(ptr(u8), base)) != 8 { return 3 }
  if deref(unchecked bitcast(ptr(u8), base + 1)) != 13 { return 4 }
  if deref(unchecked bitcast(ptr(u64), base + 8)) != 100 { return 5 }
  42
}
