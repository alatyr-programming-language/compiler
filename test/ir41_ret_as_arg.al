## IR-41 (#1786): a struct result with narrow and nested fields passed straight on as an argument — by
## address to a reader that takes a pointer, and as a field to a scalar parameter — and a three- to
## seven-word result received from and returned to legacy code. `mk3`, `mk7`, `pass` and `go` are built
## from the shared IR; `lmk7`, `lsum` and `lchk` hold a float local, which keeps them on the legacy emitter.
W3 := struct { a : u64, b : u64, c : u64 }
N := struct { w : u64, a : i32 }
S7 := struct { n : N, w : W3, z : i32, h : bool }
mk3 := fn(v : u64) -> W3 { W3(a = v, b = v + 1, c = v + 2) }
mk7 := fn(v : u64) -> S7 {
  mut s := S7(n = N(w = 65000, a = -4), w = mk3(v), z = 0, h = false)
  s.z = -100000
  s.h = true
  s
}
lmk7 := fn(v : u64) -> S7 {
  z : f64 = 1.0
  S7(n = N(w = 7, a = -1), w = W3(a = v, b = 0, c = 3), z = -8, h = true)
}
lsum := fn(w : W3) -> u64 {
  z : f64 = 2.0
  w.a + w.b + w.c
}
lchk := fn(p : ptr(S7)) -> u64 {
  z : f64 = 3.0
  if deref(p).n.a != -4 or deref(p).n.w != 65000 { return 1 }
  if deref(p).z != -100000 or not deref(p).h { return 2 }
  if deref(p).w.c != 7 { return 3 }
  0
}
take := fn(x : i32) -> u64 { if x == -100000 { return 0 }; 1 }
pass := fn() -> u64 {
  ## A three-word result straight into a legacy callee's by-value parameter.
  if lsum(mk3(10)) != 33 { return 1 }
  ## A field of a seven-word result straight into a scalar parameter.
  if take(mk7(5).z) != 0 { return 2 }
  ## The legacy result, read and re-passed.
  l := lmk7(9)
  if l.n.a != -1 or l.n.w != 7 or l.w.a != 9 or l.z != -8 or not l.h { return 3 }
  if lsum(l.w) != 12 { return 4 }
  0
}
go := fn() -> u64 {
  s := mk7(5)
  lchk(ptr(s))
}
main := fn() -> u64 {
  r1 := pass()
  if r1 != 0 { return r1 }
  r2 := go()
  if r2 != 0 { return 10 + r2 }
  42
}
## expect: run 42
