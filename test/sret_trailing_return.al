## e2e (a64 SRET, TRAILING value) — a wide-struct-returning fn whose body ENDS in a struct VALUE with
## NO explicit `return`. The trailing expression is the fn's value; for a >8-word struct return it must
## be delivered THROUGH the AAPCS64 x8 indirect-result pointer (the same SRET path the explicit-`return`
## form uses), NOT the ordinary scalar value emit. Here `mk` ends in a 10-word struct LITERAL (fields at
## 10,20,…,100); `main` binds it and sums all ten (550) / 13 = 42 — identical to wide_struct_return.al
## but exercising the trailing (implicit-return) delivery. x86_64 already handles this; guards a64 parity.
S10 := struct { a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64, i : u64, j : u64 }
mk := fn(base : u64) -> S10 {
  S10(a = base, b = base + 10, c = base + 20, d = base + 30, e = base + 40, f = base + 50, g = base + 60, h = base + 70, i = base + 80, j = base + 90)
}
main := fn() -> u64 {
  s := mk(10)
  return (s.a + s.b + s.c + s.d + s.e + s.f + s.g + s.h + s.i + s.j) / 13
}
