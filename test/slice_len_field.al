## e2e — the `.len` FIELD (not the `.len()` method) on a Slice PARAM. A slice param holds a POINTER to
## the caller's {ptr,len} block, so `.len` must double-deref it; it previously read the raw slot word (a
## garbage local) and returned junk, which made a `while i < xs.len` loop run away. Covers both a scalar
## element (Slice(u64)) and a str element (Slice(str), 2-word). Returns 42 iff both read their true len.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

scalar_len := fn(xs : Slice(u64)) -> usize { xs.len }

str_slice_len := fn(parts : Slice(str)) -> usize { parts.len }

main := fn() -> u64 {
  arr : [u64; 3] = [10, 20, 30]
  n1 := scalar_len(arr[0..3])                ## 3

  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  base := unchecked bitcast(usize, r)
  s0 := "a"
  deref(unchecked bitcast(ptr(mut usize), base)) = bitcast(usize, s0.ptr)
  deref(unchecked bitcast(ptr(mut usize), base + 8)) = s0.len
  deref(unchecked bitcast(ptr(mut usize), base + 16)) = bitcast(usize, s0.ptr)
  deref(unchecked bitcast(ptr(mut usize), base + 24)) = s0.len
  parts := Slice(str)(ptr = unchecked bitcast(ptr(str), base), len = 2)
  n2 := str_slice_len(parts)                 ## 2

  if n1 == 3 and n2 == 2 { return 42 }
  return 7
}
