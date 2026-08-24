## e2e (Types §9.4 return ABI — SRET TAIL-FORWARD). `fwd` returns a 9-word struct (> the 7-word
## register-return budget) and its return VALUE is itself a call to a wide-struct-returning fn: BOTH
## sides deliver through the hidden result pointer, so the inner call needs a destination for its own
## hidden pointer. It is staged into an aggregate temp and copied through `fwd`'s result pointer.
## Was a SILENT MISCOMPILE: `return <sret call>` matched no arm of `emit_struct_to_sret`, so the inner
## call was emitted with NO hidden pointer wired at all and the caller's destination was never written
## — `main` read an all-zero struct and exited 0 (a normal exit with a wrong value, the worst kind).
## Every field carries a DISTINCT value (base+0 .. base+8) and `main` reads the FIRST (a), a MIDDLE (e),
## the LAST (i) and a second interior pair (h - b), so a dropped, zeroed or swapped word changes the
## answer: (1 + 5 + 9) + (8 - 2) = 15 + 6 = 21.
## NB the result MUST stay < 126: this fixture also runs under the WASM sweep, and WASI `proc_exit`
## only accepts a status in [0,126) — a wider value makes wasmtime TRAP (exit 1), which the sweep would
## mis-read as a silent miscompile.
S9 := struct { a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64, i : u64 }
mk := fn(base : u64) -> S9 {
  return S9(a = base, b = base + 1, c = base + 2, d = base + 3, e = base + 4, f = base + 5, g = base + 6, h = base + 7, i = base + 8)
}
fwd := fn(base : u64) -> S9 {
  return mk(base)
}
main := fn() -> u64 {
  s := fwd(1)
  return (s.a + s.e + s.i) + (s.h - s.b)
}
