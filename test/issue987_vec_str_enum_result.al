## e2e / issue #987 — a `Vec(str)` or `Vec(E)` element read by `v[i]` keeps its whole value.
##
## The `str` and enum duals of `issue987_vec_struct_result`: `s := v[1]` over a `Vec(str)` bound the
## view as one word and lost its length, and an enum element read by `v[i]`, bound or passed straight
## on, lost its payload or segfaulted, while `vec::at(E, ptr(v), i)` was right. The lowerer now
## completes the implicit call into that explicit one before it types the result.
##
## Each check owns a code from 100 up; 42 means all held.
##
## Parent `9e60e8aa` (x86_64, omen): exit 100, `s := v[1]` had the wrong `len`.
vec := alloc::vec
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

E := enum { A, B(u64) }

tag := fn(e : E) -> u64 {
  match e {
    E.B(x) => { x }
    E.A => { 1 }
  }
}

main := fn() -> u64 {
  r := unchecked sys_mmap(std::sysno::MMAP, 0, 65536, 3, 34, bitcast(usize, 0 - 1), 0)
  mut ar := arena_over(unchecked bitcast(ptr(mut bits8), bitcast(usize, r)), 65536)

  mut v := vec::new(str, ptr(ar))
  p0 := v.push("abc")
  p1 := v.push("defgh")
  s := v[1]
  if s.len != 5 { return 100 }
  t := v.at(0)
  if t.len != 3 { return 101 }

  mut w := vec::new(E, ptr(ar))
  w0 := w.push(E.A)
  w1 := w.push(E.B(42))
  e := w[1]
  if tag(e) != 42 { return 102 }
  if tag(w[1]) != 42 { return 103 }
  if tag(w.at(0)) != 1 { return 104 }
  ws := w[0..2]
  if tag(ws[1]) != 42 { return 105 }
  42
}
## expect: run 42
