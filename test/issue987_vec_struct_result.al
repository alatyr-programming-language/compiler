## e2e / issue #987 — a `Vec` element read by `v[i]` or `v.at(i)` keeps its whole struct value.
##
## Types §4.5 makes `v.at(i)` the auto-ref call `at(T, ptr(v), i)` with `T` read from `v`'s type, and
## the driver rewrites `v[i]` to `at(v, i)`. The instance was named right (`at__S`), but the lowerer
## typed the call's RESULT only from an explicit type argument, so the implicit form answered as a bare
## scalar: `e := v[0]; e.fd` and `v[0].fd` read 0 for 42, a one-, two- or `i32`-field struct alike,
## and a struct element passed straight on (`same(v[i], x)`) handed the callee a value where its
## address was due and segfaulted. The explicit `vec::at(S, ptr(v), 0)` was right throughout.
##
## Each check owns a code from 100 up; 42 means all held.
##
## Parent `9e60e8aa` (x86_64, omen): exit 100, `e := v[0]; e.fd` read 0 (the passing shapes behind it
## each read 0 or segfaulted when run alone).
vec := alloc::vec
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

S := struct { fd : u64 }
P := struct { fd : u64, g : u64 }
W := struct { a : u64, b : u64, c : u64 }
Fd := struct { fd : i32 }

same := fn(x : S, y : S) -> bool { x.fd == y.fd }
same_w := fn(x : W, y : W) -> bool { x.a == y.a and x.b == y.b and x.c == y.c }

main := fn() -> u64 {
  r := unchecked sys_mmap(std::sysno::MMAP, 0, 65536, 3, 34, bitcast(usize, 0 - 1), 0)
  mut ar := arena_over(unchecked bitcast(ptr(mut bits8), bitcast(usize, r)), 65536)

  mut v := vec::new(S, ptr(ar))
  p0 := v.push(S(fd = 42))
  p1 := v.push(S(fd = 7))
  e := v[0]
  if e.fd != 42 { return 100 }
  if v[0].fd != 42 { return 101 }
  f := v.at(1)
  if f.fd != 7 { return 102 }
  if v.at(0).fd != 42 { return 103 }
  mut i : usize = 0
  while i < 2 {
    if not same(v[i], vec::at(S, ptr(v), i)) { return 104 }
    if not same(v.at(i), vec::at(S, ptr(v), i)) { return 105 }
    i += 1
  }

  mut q := vec::new(P, ptr(ar))
  q0 := q.push(P(fd = 40, g = 2))
  pe := q[0]
  if pe.fd + pe.g != 42 { return 106 }
  if q[0].g != 2 { return 107 }

  mut w := vec::new(W, ptr(ar))
  w0 := w.push(W(a = 1, b = 2, c = 3))
  w1 := w.push(W(a = 4, b = 5, c = 6))
  if not same_w(w[1], W(a = 4, b = 5, c = 6)) { return 108 }
  ws := w[0..2]
  if not same_w(ws[0], W(a = 1, b = 2, c = 3)) { return 109 }

  mut d := vec::new(Fd, ptr(ar))
  d0 := d.push(Fd(fd = 42))
  de := d[0]
  if u64(de.fd) != 42 { return 110 }
  42
}
## expect: run 42
