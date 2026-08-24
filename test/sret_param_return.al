## e2e (Types §9.4 return ABI — returning a wide-struct PARAM by value). A 9-word struct (> the 7-word
## register-return budget) is returned through the hidden result pointer, and the returned VALUE is a
## by-value PARAMETER. An aggregate parameter is passed BY REFERENCE (its slot holds a POINTER to the
## caller's struct, not the struct's own frame words), so the copy source is a pointer — the by-ref
## dual the SRET store used to lack. Both spellings are locked: the explicit `return v` and the
## trailing-value `{ v }`.
## Was a COMPILE-TIME CRASH (SIGILL, exit 132): the store read the param as if it were an inline frame
## struct, and its frame-word offset arithmetic UNDERFLOWED for a parameter in a low slot — a checked
## subtraction trap inside the compiler itself. The rv64 backend's `emit_rv_sret_store` already had the
## by-ref param arm; this is its x86_64 mirror.
## Every field carries a DISTINCT value (base+0 .. base+8) and `main` reads the FIRST (a), a MIDDLE (e),
## the LAST (i) and an interior pair (h - b) after TWO param round-trips, so a dropped, zeroed or
## swapped word changes the answer: with base = 2, (2 + 6 + 10) + (9 - 3) = 18 + 6 = 24.
## NB the result MUST stay < 126 (the WASM sweep's WASI `proc_exit` only accepts [0,126)).
S9 := struct { a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64, i : u64 }
mk := fn(base : u64) -> S9 {
  return S9(a = base, b = base + 1, c = base + 2, d = base + 3, e = base + 4, f = base + 5, g = base + 6, h = base + 7, i = base + 8)
}
idr := fn(v : S9) -> S9 {
  return v
}
idt := fn(v : S9) -> S9 {
  v
}
main := fn() -> u64 {
  x := mk(2)
  y := idr(x)
  z := idt(y)
  return (z.a + z.e + z.i) + (z.h - z.b)
}
