## IR-41 (#1786): a struct RESULT with a struct, an enum and a fixed-array field, crossing between
## IR-built and legacy-emitted functions in both directions. `mk` and `rd` are built from the shared IR;
## `lmk` and `lrd` hold a float local, which keeps them on the legacy emitter. The inner struct has a
## narrow signed field written negative at its own width, so the result must carry it as its canonical
## word for the legacy reader. Seven words: the register set on every target.
P := struct { x : u64, y : i16 }
K := enum { A, B(u64), C(i8) }
Q := struct { p : P, k : K, xs : [u64; 2], t : u64 }
mk := fn(v : u64) -> Q {
  mut q := Q(p = P(x = v, y = -9), k = K.C(-7), xs = [1, 2], t = 0)
  q.xs[1] = v + 1
  q.t = 77
  q
}
lmk := fn(v : u64) -> Q {
  z : f64 = 1.0
  Q(p = P(x = v, y = -300), k = K.B(v + 5), xs = [4, 5], t = 66)
}
lrd := fn() -> u64 {
  z : f64 = 2.0
  q := mk(10)
  if q.p.x != 10 { return 1 }
  if q.p.y != -9 { return 2 }
  match q.k {
    K.C(c) => { if c != -7 { return 3 } }
    K.A | K.B => { return 4 }
  }
  if q.xs[0] != 1 or q.xs[1] != 11 { return 5 }
  if q.t != 77 { return 6 }
  0
}
rd := fn() -> u64 {
  q := lmk(20)
  if q.p.x != 20 { return 1 }
  if q.p.y != -300 { return 2 }
  match q.k {
    K.B(b) => { if b != 25 { return 3 } }
    K.A | K.C => { return 4 }
  }
  if q.xs[0] != 4 or q.xs[1] != 5 { return 5 }
  if q.t != 66 { return 6 }
  m := mk(3)
  if m.p.y != -9 or m.xs[1] != 4 or m.t != 77 { return 7 }
  0
}
main := fn() -> u64 {
  r1 := lrd()
  if r1 != 0 { return r1 }
  r2 := rd()
  if r2 != 0 { return 10 + r2 }
  42
}
## expect: run 42
