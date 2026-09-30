## Issue #752 — `x := <call>?` whose `Ok` payload is a MULTI-WORD struct. The `?` value is payload
## word 0 only, and the binding stored just that word: `x.a` and `x.b` read whatever the frame held,
## so this returned 0 on x86_64, silently. The binding now stores every payload word from the return
## registers. The first field is a `u8` in the second function so a narrow word 0 is covered too, and
## the other shapes the defect reached are covered as well: `?` on an enum local (`z := r?`), and a
## field read straight off `?` at a non-zero offset (`f(3)?.b`, `r?.a`), which read the wrong word.
T := struct { k : u64, a : u64, b : u64 }
U := struct { k : u8, a : u64, b : u64 }
f := fn(n : u64) -> Result(T, u64) { Result(T, u64).Ok(T(k = n, a = 20, b = 2)) }
h := fn(n : u64) -> Result(U, u64) { Result(U, u64).Ok(U(k = 3, a = n, b = 10)) }
g := fn() -> Result(u64, u64) {
  x := f(1)?
  y := h(10)?
  r := f(2)
  z := r?
  Result(u64, u64).Ok(x.a + x.b + y.a + y.b + z.a - 20 + f(3)?.b - 2 + r?.a - 20)
}
main := fn() -> u64 {
  match g() { Result::Ok(v) => { return v } Result::Err(e) => { return 1 } }
  0
}
