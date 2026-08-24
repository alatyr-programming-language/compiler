## e2e — alloc::vec accessors added this cycle: try_at (bounds-checked by-value read → Option, distinct
## from the unchecked trap-on-OOB `at`) and swap_remove (O(1) unordered removal). Push [10,20,30,40],
## then check try_at in/out of range and that swap_remove(1) returns 20 and moves the last element (40)
## into slot 1. Returns 42 iff all exact.
vec := alloc::vec
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

expect_some := fn(o : Option(u64), want : u64) -> bool {
  match o {
    Option::Some(x) => { x == want }
    Option::None => { false }
  }
}
is_none := fn(o : Option(u64)) -> bool {
  match o {
    Option::Some(x) => { false }
    Option::None => { true }
  }
}

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut v := vec::with_capacity(u64, ptr(ar), 16)
  vec::push(u64, v, 10).expect("push")
  vec::push(u64, v, 20).expect("push")
  vec::push(u64, v, 30).expect("push")
  vec::push(u64, v, 40).expect("push")

  a1 := vec::try_at(u64, ptr(v), 1)
  if not expect_some(a1, 20) { return 1 }
  a9 := vec::try_at(u64, ptr(v), 4)
  if not is_none(a9) { return 2 }

  rm := vec::swap_remove(u64, v, 1)                 ## removes 20; moves 40 into slot 1
  if not expect_some(rm, 20) { return 5 }
  if vec::vlen(u64, ptr(v)) != 3 { return 6 }
  moved := vec::try_at(u64, ptr(v), 1)
  if not expect_some(moved, 40) { return 7 }        ## last element now sits at slot 1
  return 42
}
