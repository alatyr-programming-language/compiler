## e2e (base/slice `contains` + `find` over a Slice view). `contains(T, s, x)` — membership by `==`;
## `find(T, s, pred)` — first index satisfying a fn-value predicate, as `Option(usize)`. Build a
## Vec {10,20,3,40}, take a Slice view, then: contains 20 (true, +1), contains 99 (false, +0),
## find `x==3` → Some(2) (+2*10=20). 1 + 20 = 21 (run-code). Exercises a fn-value predicate called
## INDIRECTLY through a param, a parameterized `Option(usize)` enum return, and `s[i]` slice indexing
## — the base-prelude higher-order slice surface (regression guard: `contains` used a for-over-slice
## loop the lean parser mis-parsed as a range-`for`, over-running its `}` and ABSORBING `find`'s body
## into `contains` — so `find`'s `pred`/`Option` were emitted under the wrong label and never linked).
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
is_three := fn(x : u64) -> bool { return x == 3 }
main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut v := alloc::vec::new(u64, ptr(ar))
  alloc::vec::push(u64, v, 10).expect("p")
  alloc::vec::push(u64, v, 20).expect("p")
  alloc::vec::push(u64, v, 3).expect("p")
  alloc::vec::push(u64, v, 40).expect("p")
  s := alloc::vec::as_slice(u64, ptr(v))
  mut r2 : u64 = 0
  if contains(u64, s, 20) { r2 = r2 + 1 }
  if contains(u64, s, 99) { r2 = r2 + 100 }
  fr := find(u64, s, is_three)
  match fr {
    Option::Some(i) => { r2 = r2 + u64(i) * 10 }
    Option::None => { r2 = r2 + 1000 }
  }
  r2
}
