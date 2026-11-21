## IR-41 (#1786): an eight-word struct result with narrow and nested fields. x86_64's convention returns
## eight words through a hidden result address (its register set holds seven), aarch64 and riscv64 in
## eight result registers: each target's IR-built side must take the result the way its legacy side does,
## or leave the call to it. `mk` and `rd` are built from the shared IR; `lmk` and `lrd` hold a float
## local, which keeps them on the legacy emitter.
P := struct { x : u64, y : i32 }
E := struct { p : P, q : P, a : u8, b : i8, c : u64, d : u64 }
mk := fn(v : u64) -> E {
  mut e := E(p = P(x = 1, y = -2), q = P(x = 3, y = 4), a = 0, b = 0, c = 0, d = v)
  e.b = -6
  e.a = 250
  e.c = v + 1
  e
}
lmk := fn(v : u64) -> E {
  z : f64 = 1.0
  E(p = P(x = v, y = -20), q = P(x = 30, y = 40), a = 5, b = -60, c = 70, d = 80)
}
lrd := fn() -> u64 {
  z : f64 = 2.0
  e := mk(9)
  if e.p.x != 1 or e.p.y != -2 { return 1 }
  if e.q.x != 3 or e.q.y != 4 { return 2 }
  if e.a != 250 or e.b != -6 { return 3 }
  if e.c != 10 or e.d != 9 { return 4 }
  0
}
rd := fn() -> u64 {
  e := lmk(10)
  if e.p.x != 10 or e.p.y != -20 { return 1 }
  if e.q.x != 30 or e.q.y != 40 { return 2 }
  if e.a != 5 or e.b != -60 { return 3 }
  if e.c != 70 or e.d != 80 { return 4 }
  f := mk(2)
  if f.p.y != -2 or f.b != -6 or f.c != 3 { return 5 }
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
