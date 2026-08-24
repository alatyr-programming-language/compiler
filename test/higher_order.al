## e2e (HIGHER-ORDER stdlib: `alloc::vec::filter` over a fn-value predicate). The capstone of the
## allocating slice/vec algorithms: build a `Vec(u64)` {1..9}, take a `Slice` view (`as_slice`),
## then `filter` it with the fn-value `gt2` (`x > 2`) into a NEW arena-backed `Vec` — {3,4,5,6,7,8,9}.
## Sum the filtered elements (a second `as_slice` + slice-index read) = 3+4+5+6+7+8+9 = 42. Exercises,
## end to end: fn-values, generic monomorphization, the `Slice` prelude (`as_slice` returns `Slice(T)`),
## slice-value indexing (`s[i]` derefs the ptr field), a discarded `push(...).expect(...)` mutator
## inside `filter`, and a 4-word `Vec` returned from a generic fn. Before this session's fixes the
## whole path failed to even LINK (a range-slice parse-drift swallowed `filter`).
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
gt2 := fn(x : u64) -> bool { return x > 2 }
main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut v := alloc::vec::new(u64, ptr(ar))
  mut i : u64 = 1
  while i <= 9 {
    alloc::vec::push(u64, v, i).expect("push")
    i = i + 1
  }
  s := alloc::vec::as_slice(u64, ptr(v))
  mut fv := alloc::vec::filter(u64, ptr(ar), s, gt2)
  fs := alloc::vec::as_slice(u64, ptr(fv))
  mut sum : u64 = 0
  mut j : usize = 0
  while j < fs.len {
    sum = sum + fs[j]
    j = j + 1
  }
  u64(sum)
}
