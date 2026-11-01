## e2e / issue #987 — a UFCS call into a `ptr(Vec(T))` parameter infers `T` from the receiver.
##
## `at`, `index_set` and `index_range` take the `Vec` by scoped reference (`v : ptr(Vec(T))`), and
## Types §4.5 makes `v.at(i)` the auto-ref call `at(ptr(v), i)`, with `T` read from `v`'s type. The
## inference looked only at the parameter type's own arguments (`ptr(...)` has `Vec(T)`, not `T`), so
## `v.at(0)` and `v.index_set(0, x)` were refused ("this generic call omits its comptime type
## argument and it cannot be inferred here"), and `v.index_range(0, 2)` was tagged by the receiver's
## name and crashed at run time. A sub-word `Vec(u16)` checks the inferred instance's stride too.
##
## Each check owns a code from 100 up; 42 means all held.
##
## Parent `7bb90a3a` (x86_64, omen): the build is refused (rc 1), the generic call "cannot be
## inferred here", where a run to 42 was due.
vec := alloc::vec
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  r := unchecked sys_mmap(std::sysno::MMAP, 0, 65536, 3, 34, bitcast(usize, 0 - 1), 0)
  mut ar := arena_over(unchecked bitcast(ptr(mut bits8), bitcast(usize, r)), 65536)

  mut v := vec::new(u64, ptr(ar))
  p0 := v.push(40)
  p1 := v.push(1)
  if v.at(0) + v.at(1) != 41 { return 100 }
  v.index_set(1, 2)
  if vec::at(u64, ptr(v), 1) != 2 { return 101 }
  s := v.index_range(0, 2)
  if s[0] + s[1] != 42 { return 102 }

  mut h := vec::new(u16, ptr(ar))
  q0 := h.push(30)
  q1 := h.push(5)
  q2 := h.push(7)
  h.index_set(1, 9)
  e1 : u16 = h.at(1)
  if u64(e1) != 9 { return 103 }
  e2 : u16 = vec::at(u16, ptr(h), 2)
  if u64(e2) != 7 { return 104 }
  ## A sub-word `index_range` view is not read here: its elements read 8 bytes wide (#1238).

  f := v.free()
  g := h.free()
  42
}
## expect: run 42
