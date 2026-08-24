## e2e (Types §9.4 return ABI — a wide (SRET) call NESTED inside another wide (SRET) call's argument).
## `sumf(bump(mk(1)))`: `mk`'s 9-word result materializes into an aggregate-value temp block, `bump`
## consumes it and materializes ITS 9-word result into a SECOND block, and `sumf` reads that. The two
## blocks are live at the same time (`emit_call_args` saves the pool bump pointer, so a nested call's
## args stack ABOVE the outer call's still-live slices), so the frame must reserve TWO — but the pool
## sizing took a flat MAX of the per-call aggregate-value-argument counts (1 here) instead of summing
## the nesting, and the program died on a loud `aggregate-value call-arg temp pool overflow` abort.
## Loud, never silent — but aarch64 already compiled and ran the same program because its reservation
## (`a64_aggval_words_e`) counts TREE-WIDE; x86_64 now mirrors that by adding the deepest argument
## subtree's requirement to the call's own count.
## Every field carries a distinct value and each reader takes the FIRST (a), a MIDDLE (e) and the LAST
## (i), and `bump` increments exactly those three — so a dropped, zeroed or aliased block shows up.
## Values: mk(1) = {1..9}; bump → a=2, e=6, i=10; sumf = 2 + 6 + 10 = 18.
## NB the result MUST stay < 126 (the WASM sweep's WASI `proc_exit` only accepts [0,126)).
S9 := struct { a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64, i : u64 }

mk := fn(base : u64) -> S9 {
  return S9(a = base, b = base + 1, c = base + 2, d = base + 3, e = base + 4, f = base + 5, g = base + 6, h = base + 7, i = base + 8)
}

bump := fn(s : S9) -> S9 {
  return S9(a = s.a + 1, b = s.b, c = s.c, d = s.d, e = s.e + 1, f = s.f, g = s.g, h = s.h, i = s.i + 1)
}

sumf := fn(c : S9) -> u64 {
  return c.a + c.e + c.i
}

main := fn() -> u64 {
  return sumf(bump(mk(1)))
}
