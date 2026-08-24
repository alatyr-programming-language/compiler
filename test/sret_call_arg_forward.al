## e2e (Types §9.4 return ABI — a wide (SRET) TAIL-FORWARDED call used directly as a by-value aggregate
## ARGUMENT). Composes the two wide-return corners in one expression: `fwd` returns a 9-word struct (> the
## 7-word register-return budget) by tail-forwarding its OWN hidden result pointer to `mk`, and that call is
## then handed straight to `sumf` / `two` as a by-value aggregate argument — so the argument materialization
## allocates an aggregate temp, hands ITS address down as `fwd`'s hidden result pointer, `fwd` forwards that
## same pointer on to `mk`, and `mk` writes the 9 words two frames down into the caller's temp.
## On aarch64 the forwarded pointer is the AAPCS64 x8 indirect-result register, reloaded from the callee's
## own spill slot (`ldr x8, [x29, #slot]`) rather than pointing at a frame block of its own.
## `two(fwd(1), fwd(2))` additionally locks that TWO wide-returning call args in ONE call get DISTINCT temp
## blocks even when the wide return arrives through a forwarding hop — sharing one would alias and both
## parameters would read the same struct.
## Every field carries a DISTINCT value (base+0 .. base+8) and each reader takes the FIRST (a), a MIDDLE (e)
## and the LAST (i), so a dropped, zeroed or swapped word changes the answer.
## Values: sumf(fwd(1)) = 1 + 5 + 9 = 15; two(fwd(1), fwd(2)) = (1 + 9) + (2 + 10) = 22 → 37.
## NB the result MUST stay < 126 (the WASM sweep's WASI `proc_exit` only accepts [0,126)).
S9 := struct { a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64, i : u64 }
mk := fn(base : u64) -> S9 {
  return S9(a = base, b = base + 1, c = base + 2, d = base + 3, e = base + 4, f = base + 5, g = base + 6, h = base + 7, i = base + 8)
}
fwd := fn(base : u64) -> S9 {
  return mk(base)
}
sumf := fn(c : S9) -> u64 {
  return c.a + c.e + c.i
}
two := fn(x : S9, y : S9) -> u64 {
  return (x.a + x.i) + (y.a + y.i)
}
main := fn() -> u64 {
  return sumf(fwd(1)) + two(fwd(1), fwd(2))
}
