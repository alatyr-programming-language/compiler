## IR slice 3b (`docs/ir-slice-3.md` §6): memory crosses between IR-built and legacy-emitted functions
## through pointers, so both must lay a type out alike (`docs/ir.md` §3.7, rule 7.1.1). For a
## WORD-tier struct (every field one 8-byte word) and an 8-byte scalar that agreement is proved here in
## both directions: the IR writes and a legacy function reads, then the reverse. The `l*` functions
## each hold a float local, which keeps them on the legacy emitter until slice 8 builds floats; `main`,
## `put`, `get` and `bump` are IR-built on aarch64/riscv64. Answers 42 everywhere.
S := struct { a : i64, b : u64 }
put := fn(p : ptr(mut S), x : i64) {
  p.a = x
  deref(p).b = 7
}
get := fn(p : ptr(S)) -> i64 { p.a + i64(deref(p).b) }
lput := fn(p : ptr(mut S), x : i64) {
  f : f64 = 1.0
  p.a = x
  p.b = 9
}
lget := fn(p : ptr(S)) -> i64 {
  f : f64 = 2.0
  p.a + i64(p.b)
}
bump := fn(q : ptr(mut u64)) { deref(q) = deref(q) + 5 }
lbump := fn(q : ptr(mut u64)) {
  f : f64 = 3.0
  deref(q) = deref(q) + 6
}
main := fn() -> u64 {
  mut s := S(a = 1, b = 2)
  put(ptr(mut s), 0 - 30)
  r1 := lget(ptr(s))
  lput(ptr(mut s), 50)
  r2 := get(ptr(s))
  mut n : u64 = 10
  bump(ptr(mut n))
  lbump(ptr(mut n))
  if r1 == 0 - 23 and r2 == 59 and n == 21 { return 42 }
  1
}
