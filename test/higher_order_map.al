## e2e (HIGHER-ORDER `alloc::vec::map` — a TWO-type-param generic `map(T, U, …) -> Vec(U)`). Build a
## `Vec(u64)` {1..6}, `map` it with the fn-value `dbl` (`x*2`) into a NEW `Vec(u64)` {2,4,6,8,10,12},
## sum via a slice read = 42. Exercises the 2-type-param monomorphization end to end: BOTH type-args
## erased + bound + mangled (`…__map__u64__u64`), and the NESTED substitution (`map`'s body calls
## `vec_in(U, …)` → `allocate(…, U, …)`, U resolved to the instance's concrete type). Before the
## multi-type-param work, `map` could not be monomorphized at all (only one type-arg was handled).
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
dbl := fn(x : u64) -> u64 { return x * 2 }
main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut v := alloc::vec::new(u64, ptr(ar))
  mut i : u64 = 1
  while i <= 6 {
    alloc::vec::push(u64, v, i).expect("push")
    i = i + 1
  }
  s := alloc::vec::as_slice(u64, ptr(v))
  mut m := alloc::vec::map(u64, u64, ptr(ar), s, dbl)
  ms := alloc::vec::as_slice(u64, ptr(m))
  mut sum : u64 = 0
  mut j : usize = 0
  while j < ms.len {
    sum = sum + ms[j]
    j = j + 1
  }
  u64(sum)
}
