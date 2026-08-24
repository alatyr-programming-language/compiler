## e2e (Types §9.4 return ABI — a wide (SRET) struct-returning CALL in ARGUMENT position). `mk` returns
## a 9-word struct (> the 7-word register-return budget) through the hidden result pointer, and here its
## result is handed straight to another call as a by-value aggregate argument — with no destination
## local to point that hidden pointer at. The argument materialization allocates an aggregate temp,
## hands ITS address down as the callee's hidden result pointer, and then passes that same block by
## reference (the aggregate-parameter ABI). Was a SEGFAULT: the call fell through to the scalar
## argument path with NO hidden pointer set up, so `mk` wrote its 9 words through whatever %rdi
## happened to hold.
## `two(mk(1), mk(2))` additionally locks that TWO wide-returning call args in ONE call get DISTINCT
## temp blocks — sharing one would alias and both parameters would read the same struct.
## Values: sumf(mk(1)) = 1 + 5 + 9 = 15; two(mk(1), mk(2)) = (1 + 9) + (2 + 10) = 22 → 37.
## NB the result MUST stay < 126 (the WASM sweep's WASI `proc_exit` only accepts [0,126)).
S9 := struct { a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64, i : u64 }
mk := fn(base : u64) -> S9 {
  return S9(a = base, b = base + 1, c = base + 2, d = base + 3, e = base + 4, f = base + 5, g = base + 6, h = base + 7, i = base + 8)
}
sumf := fn(c : S9) -> u64 {
  return c.a + c.e + c.i
}
two := fn(x : S9, y : S9) -> u64 {
  return (x.a + x.i) + (y.a + y.i)
}
main := fn() -> u64 {
  return sumf(mk(1)) + two(mk(1), mk(2))
}
