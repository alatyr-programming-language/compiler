## e2e — REGALLOC: CHECKED `/` and `%` on the register-allocated scalar-leaf IR path (no `unchecked`).
## On x86 a checked division's div-by-zero / signed INT_MIN-overflow trap is the hardware #DE (SIGFPE)
## raised by the plain `divq`/`idivq` — exactly what the reference text path emits for a checked division
## (no software guard) — so the IR path admits checked division directly. `dm` is scalar-leaf (native
## scalar params + return, only `/` and `%`) → the register-allocated IR path. Same exit whether built
## default (regalloc) or ALATYR_RA=0 (text stack machine). 122/3 = 40, 122%3 = 2 → 40 + 2 = 42.
dm := fn(a : u64, b : u64) -> u64 { (a / b) + (a % b) }
main := fn() -> u64 {
  dm(122, 3)
}
