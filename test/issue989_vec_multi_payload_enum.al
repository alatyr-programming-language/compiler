## e2e / issue #989 — a `Vec(E)` of a multi-payload enum reads back the variant and payload it stored.
##
## `Vec(T).at` returns `deref(elem)`. At `T = E` that is an enum VALUE read through a pointer, and the
## enum-value emitter had no arm for it: it fell into the catch-all that emits a null enum
## (discriminant 0, payload 0), so every element read back as `E.C(0)`. The store side was right:
## `push` copies all three words of the element.
##
## Three elements, each of a different variant and with distinct non-zero payload words, so a
## dropped or shifted word cannot pass as a zero. Each check owns a code from 100 up; 42 means every
## element came back whole.
##
## Parent `55fa477` (x86_64, omen): built rc 0, ran to 101 where 42 was due (element 0 matched as
## `E.C(0)`, not `E.C(40)`). The issue's own program ran to 100 there.
vec := alloc::vec
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
E := enum { C(u64), A(usize, usize), N }

## 1 for `C(k)`, 2 for `A(x, y)`, 3 for `N`, with the payload folded in so one compare checks all.
code := fn(e : E) -> u64 {
  match e {
    E.C(k) => { 1000 + k }
    E.A(x, y) => { 2000 + u64(x) * 10 + u64(y) }
    E.N => { 3000 }
  }
}

main := fn() -> u64 {
  r := unchecked sys_mmap(std::sysno::MMAP, 0, 65536, 3, 34, bitcast(usize, 0 - 1), 0)
  mut ar := arena_over(unchecked bitcast(ptr(mut bits8), bitcast(usize, r)), 65536)
  mut v := vec::new(E, ptr(ar))
  x0 := vec::push(E, v, E.C(40))
  x1 := vec::push(E, v, E.A(7, 3))
  x2 := vec::push(E, v, E.N)
  e0 : E = vec::at(E, ptr(v), 0)
  if code(e0) != 1040 { return 101 }
  e1 : E = vec::at(E, ptr(v), 1)
  if code(e1) != 2073 { return 102 }
  e2 : E = vec::at(E, ptr(v), 2)
  if code(e2) != 3000 { return 103 }
  ## Read back again after the others, so an element is not only right because it was last written.
  e0b : E = vec::at(E, ptr(v), 0)
  if code(e0b) != 1040 { return 104 }
  vec::free(E, v)
  42
}
