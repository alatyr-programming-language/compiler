## e2e — a typed array-SLICE bound to a LOCAL (`s := arr[lo..hi]`) then passed as an ARGUMENT. The slice
## local stores its {ptr,len} pair directly in its two frame words; passing it must hand the callee the
## local's ADDRESS (a pointer to that block), not word 0 (the data ptr) — else the callee double-deref'd
## and read a garbage len (`s.len` = junk, so `f(s)` truncated). Covers a scalar Slice(u64) and a str
## Slice(str) local arg, checking both len and an element. Returns 42 iff exact.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

sum_len := fn(xs : Slice(u64)) -> u64 {
  mut t : u64 = 0
  mut i : usize = 0
  while i < xs.len() { t += xs[i]; i += 1 }
  t
}
slen := fn(parts : Slice(str)) -> usize { parts.len() }

main := fn() -> u64 {
  arr : [u64; 4] = [10, 20, 30, 40]
  s := arr[0..4]                        ## scalar slice LOCAL
  if sum_len(s) != 100 { return 1 }     ## 10+20+30+40, over the whole (correct-len) slice

  ## a str slice local built over an arena page (up-growing), then passed
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  base := unchecked bitcast(usize, r)
  s0 := "ab"
  deref(unchecked bitcast(ptr(mut usize), base)) = bitcast(usize, s0.ptr)
  deref(unchecked bitcast(ptr(mut usize), base + 8)) = s0.len
  deref(unchecked bitcast(ptr(mut usize), base + 16)) = bitcast(usize, s0.ptr)
  deref(unchecked bitcast(ptr(mut usize), base + 24)) = s0.len
  sv := Slice(str)(ptr = unchecked bitcast(ptr(str), base), len = 2)   ## str slice LOCAL
  if slen(sv) != 2 { return 2 }

  return 42
}
