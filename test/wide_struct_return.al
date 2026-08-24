## e2e (SRET — returning a struct WIDER than the 7-register return convention). A fn returning a
## struct of > 7 words can't fit %rax:%rdx:%rcx:%r8:%r9:%r10:%r11, so it uses the SysV sret path: the
## caller passes the destination local's ADDRESS as a hidden %rdi arg, the callee writes the whole
## struct through it (down-growing) + returns the pointer in %rax. Here a 10-word struct is built in
## `mk` and returned; `main` binds it and sums all ten fields (10+20+…+100 = 550), /13 = 42. Guards
## the wide-aggregate-value return path (≤7-word register returns are unchanged / byte-identical).
S10 := struct { a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64, i : u64, j : u64 }
mk := fn(base : u64) -> S10 {
  v := S10(a = base, b = base + 10, c = base + 20, d = base + 30, e = base + 40, f = base + 50, g = base + 60, h = base + 70, i = base + 80, j = base + 90)
  return v
}
main := fn() -> u64 {
  s := mk(10)
  return (s.a + s.b + s.c + s.d + s.e + s.f + s.g + s.h + s.i + s.j) / 13
}
