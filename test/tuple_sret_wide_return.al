## e2e (Types §9.4 return ABI — WIDE TUPLE return via SRET). A tuple return was ALWAYS read back from
## the return registers (`emit_retreg`, %rax:%rdx:%rcx:%r8:%r9:%r10:%r11 = 7 words); a tuple with 8+
## components therefore delivered garbage for every component past the 7th — a SILENT MISCOMPILE (a
## normal exit with a wrong value). A wide tuple now rides the SAME hidden-result-pointer (SRET) path
## a wide struct / wide enum does: the caller hands the destination local's word-0 address down in
## %rdi and the callee writes every component through it.
## BOUNDARY: `mk7` (7 components) stays on the register path unchanged; `mk10` (10) takes SRET.
## Both a tuple LITERAL return (`mk10`) and a tuple LOCAL return (`mkloc`) are exercised, and every
## component carries a DISTINCT value so a dropped/zeroed/swapped word changes the answer.
##   mk10(1):  t.0 = 1, t.7 = 8, t.9 = 10          -> 1 + 8 + 10 = 19
##   mkloc(2): u.0 = 2, u.8 = 10, u.9 = 11         -> 2 + 10 + 11 = 23
##   mk7(3):   v.0 = 3, v.6 = 9                    -> 3 + 9 = 12
## total = 19 + 23 + 12 = 54.
## NB the result MUST stay < 126: this fixture also runs under the WASM sweep, and WASI `proc_exit`
## only accepts a status in [0,126) — a wider value makes wasmtime TRAP (exit 1), which the sweep
## would mis-read as a silent miscompile.
mk10 := fn(b : u64) -> (u64, u64, u64, u64, u64, u64, u64, u64, u64, u64) {
  return (b, b + 1, b + 2, b + 3, b + 4, b + 5, b + 6, b + 7, b + 8, b + 9)
}
mkloc := fn(b : u64) -> (u64, u64, u64, u64, u64, u64, u64, u64, u64, u64) {
  t := (b, b + 1, b + 2, b + 3, b + 4, b + 5, b + 6, b + 7, b + 8, b + 9)
  return t
}
mk7 := fn(b : u64) -> (u64, u64, u64, u64, u64, u64, u64) {
  return (b, b + 1, b + 2, b + 3, b + 4, b + 5, b + 6)
}
main := fn() -> u64 {
  t := mk10(1)
  u := mkloc(2)
  v := mk7(3)
  return u64(t.0 + t.7 + t.9) + u64(u.0 + u.8 + u.9) + u64(v.0 + v.6)
}
