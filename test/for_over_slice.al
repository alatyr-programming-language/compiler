## e2e (for-over-ITERABLE `for x in <slice>` — the loop var binds each ELEMENT, not an index). The
## lean statement `for` parser was RANGE-only (`for i in lo .. hi`); this adds the no-`..` form,
## desugared in the lower to a counted loop over the slice's {ptr,len} (`__i = 0; while __i < s.len {
## x := s[__i] ; … ; __i += 1 }`). Build a Vec {10,20,12}, take a Slice view, sum the elements via
## `for el in s` = 42. Scalar elements over a Slice VAR (aggregate elements / non-var iterables are
## future work). Also the axis-B dogfood: base/slice `contains` now uses this form.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut v := alloc::vec::new(u64, ptr(ar))
  alloc::vec::push(u64, v, 10).expect("p")
  alloc::vec::push(u64, v, 20).expect("p")
  alloc::vec::push(u64, v, 12).expect("p")
  s := alloc::vec::as_slice(u64, ptr(v))
  mut sum : u64 = 0
  for el in s {
    sum = sum + el
  }
  sum
}
