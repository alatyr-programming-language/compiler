## e2e — reading a `Slice(str)` ELEMENT as a full 2-word {ptr,len} value. A str-element slice binds
## `eek == 4`/`estride == 2` (previously it fell through and the element was read as one word — the ptr
## — silently zeroing the len). Builds the {ptr,len} entry table in a raw mmap page (up-growing, the
## shape std::os::args produces), views it as a Slice(str), and reads element 1 both by whole-value
## bind (`e := parts[i]`) and by field (`e.len`, `bytes(e)[0]`). Returns 42 iff both agree.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

## whole-value read: bind the element, then read its ptr (first byte) and len — proves both words land.
elem_code := fn(parts : Slice(str), i : usize) -> u64 {
  e := parts[i]
  b := bytes(e)
  u64(e.len) * 1000 + u64(b[0])
}

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  base := unchecked bitcast(usize, r)
  s0 := "hi"
  s1 := "Bye"
  deref(unchecked bitcast(ptr(mut usize), base)) = bitcast(usize, s0.ptr)
  deref(unchecked bitcast(ptr(mut usize), base + 8)) = s0.len
  deref(unchecked bitcast(ptr(mut usize), base + 16)) = bitcast(usize, s1.ptr)
  deref(unchecked bitcast(ptr(mut usize), base + 24)) = s1.len
  parts := Slice(str)(ptr = unchecked bitcast(ptr(str), base), len = 2)
  ## element 1 = "Bye": len 3, first byte 'B' == 66  ->  3*1000 + 66 = 3066
  ## element 0 = "hi":  len 2, first byte 'h' == 104 ->  2*1000 + 104 = 2104
  if elem_code(parts, 1) == 3066 and elem_code(parts, 0) == 2104 { return 42 }
  return 7
}
