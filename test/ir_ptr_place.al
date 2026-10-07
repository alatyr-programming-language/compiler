## IR slice 3b (`docs/ir-slice-3.md` §6): pointers as places on the IR-built register twins — a field read
## and written through `p.f` and `deref(p).f`, a scalar through `deref(q)`, `ptr(x)` of a struct local
## and of an address-taken scalar local (which then lives in memory: a write through the pointer is
## seen by the name, and a write to the name through the pointer). Every function here is IR-built on
## aarch64/riscv64; the legacy twins trapped on the field places. Answers 42 everywhere.
S := struct { a : i64, b : u64 }
scale := fn(p : ptr(mut S), k : i64) {
  p.a = p.a * k
  deref(p).b = deref(p).b + u64(k)
}
add := fn(q : ptr(mut i64), d : i64) { deref(q) = deref(q) + d }
main := fn() -> u64 {
  mut s := S(a = 0 - 4, b = 1)
  scale(ptr(mut s), 3)
  mut n : i64 = 5
  add(ptr(mut n), 10)
  n = n + 1
  add(ptr(mut n), 0 - 2)
  if s.a == 0 - 12 and s.b == 4 and n == 14 { return 42 }
  1
}
