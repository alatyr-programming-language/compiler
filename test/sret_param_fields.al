## e2e (SRET from a wide-struct PARAM's fields, TWO arguments) — S9 is 9 u64 words (> 8, the register
## return budget), so `bump` returns via the indirect-result convention (RISC-V LP64: the destination
## pointer arrives in a0 and the real arguments shift up to a1..a7; AAPCS64 uses x8). The callee reads its
## BY-REFERENCE struct param `v` and its SECOND scalar argument `k`, so a mis-shifted argument register
## changes the answer. Fields hold distinct values at distinct offsets; main reads the FIRST (a), a MIDDLE
## (e) and the LAST (i) field of the result: (1+10) + (5+10) + (9+10) = 45. NB the result MUST stay < 126 —
## this fixture is swept under WASI too, whose `proc_exit` only accepts a status in [0,126).
S9 := struct { a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64, i : u64 }
bump := fn(v : S9, k : u64) -> S9 {
  return S9(a = v.a + k, b = v.b, c = v.c, d = v.d, e = v.e + k, f = v.f, g = v.g, h = v.h, i = v.i + k)
}
main := fn() -> u64 {
  s := S9(a = 1, b = 2, c = 3, d = 4, e = 5, f = 6, g = 7, h = 8, i = 9)
  u := bump(s, 10)
  return u.a + u.e + u.i
}
