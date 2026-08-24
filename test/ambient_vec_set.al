## e2e — the generic `alloc::vec` container through the AMBIENT path (no Rust seed), exercising the
## MUTATE-IN-PLACE surface beyond `vec_container`'s new+push+at: `set(T, in out v, i, x)` overwrites
## an element (an `in out Vec(T)` mutator), then three `at(T, ptr(v), i)` reads confirm the store
## landed. push 10,20,99 → set index 2 to 12 → 10 + 20 + 12 = 42. Guards the ambient generic
## `set`/`at` path (explicit type-arg `u64`). Raw `@abi(syscall)` mmap so the test is self-contained.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut v := alloc::vec::new(u64, ptr(ar))
  alloc::vec::push(u64, v, 10).expect("push")
  alloc::vec::push(u64, v, 20).expect("push")
  alloc::vec::push(u64, v, 99).expect("push")
  alloc::vec::set(u64, v, 2, 12)
  s := alloc::vec::at(u64, ptr(v), 0)
  t := alloc::vec::at(u64, ptr(v), 1)
  u := alloc::vec::at(u64, ptr(v), 2)
  return s + t + u
}
