## e2e — alloc::string::join over a Slice(str): concatenates the parts with a separator into a NEW owned
## String. The {ptr,len} entry table is built up-growing in a raw mmap page (the std::os::args shape),
## viewed as a Slice(str), and joined; the result is read back via as_str. Exercises the str-element
## whole-value read inside a loop (bound to a local, then passed to push_str) — the join hot path.
## Returns 42 iff exact.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
strm := alloc::string

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  rt0 := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  tbase := unchecked bitcast(usize, rt0)
  rs0 := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  mut ar := arena_over(unchecked bitcast(ptr(mut bits8), bitcast(usize, rs0)), 65536)
  s0 := "one"
  s1 := "two"
  s2 := "three"
  deref(unchecked bitcast(ptr(mut usize), tbase)) = bitcast(usize, s0.ptr)
  deref(unchecked bitcast(ptr(mut usize), tbase + 8)) = s0.len
  deref(unchecked bitcast(ptr(mut usize), tbase + 16)) = bitcast(usize, s1.ptr)
  deref(unchecked bitcast(ptr(mut usize), tbase + 24)) = s1.len
  deref(unchecked bitcast(ptr(mut usize), tbase + 32)) = bitcast(usize, s2.ptr)
  deref(unchecked bitcast(ptr(mut usize), tbase + 40)) = s2.len
  parts := Slice(str)(ptr = unchecked bitcast(ptr(str), tbase), len = 3)
  jn := strm::join(ptr(ar), parts, ", ")
  sj := strm::as_str(ptr(jn))
  if sj == "one, two, three" { return 42 }
  return 7
}
