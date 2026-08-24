## e2e — direct field access through a `get` pointer: `deref(get(P, ar, h)).x`. `p := get(P, ar, h)`
## binds `p` as a pointer-to-struct (ek 7) even though `get` is GENERIC (returns `scoped ptr(mut T)`,
## T → P resolved from the type argument), so the field reads resolve THROUGH the pointer without a
## whole-struct copy. Complements `ambient_alloc_into_struct` (which uses the `s := deref(get(…))` copy).
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

P := struct { x : u64, y : u64 }

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  @alloc(ar) h := P(x = 40, y = 2)
  p := get(P, ar, h)
  return deref(p).x + deref(p).y
}
