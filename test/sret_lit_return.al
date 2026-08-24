## e2e (SRET — a wide struct returned as a struct LITERAL directly, not via a named local). S9 is 9 u64
## words (> 8, the register-return budget) → the AArch64 indirect-result (x8) path: the caller passes the
## destination address in x8, the callee writes the literal's fields straight through it. Distinct per-field
## values (1..9) at non-zero offsets so a dropped/swapped field would change the answer. main reads the
## FIRST (s.a=1), a MIDDLE (s.e=5), and the LAST (s.i=9) field: 1 + 5 + 9 = 15.
## NB the result MUST stay < 126: this fixture also runs under the WASM sweep, and WASI `proc_exit` only
## accepts a status in [0,126) — a wider value (e.g. 150) makes wasmtime TRAP (exit 1), which the sweep
## would mis-read as a silent miscompile. Native/qemu allow 0..255; WASI is the tighter constraint.
S9 := struct { a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64, i : u64 }
mk := fn() -> S9 {
  return S9(a = 1, b = 2, c = 3, d = 4, e = 5, f = 6, g = 7, h = 8, i = 9)
}
main := fn() -> u64 {
  s := mk()
  return s.a + s.e + s.i
}
