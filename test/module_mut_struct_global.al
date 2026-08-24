## e2e — MUTABLE struct module GLOBAL (`mut CFG := Cfg(...)`). A struct global gets `.data` storage
## as N ascending 8-byte cells (`LABEL + k*8`, field-declaration order); a field read loads its cell,
## a field write stores it — shared mutable state across functions. `tick` (a separate fn) mutates the
## SAME cells `main` reads. Two ticks: a = 1+10+10 = 21; c = (2+3)=5 then (2+5)=7. Returns 21+7 = 28... 42.
Cfg := struct { a : u64, b : u64, c : u64 }
mut CFG := Cfg(a = 1, b = 2, c = 3)
tick := fn() {
  CFG.a = CFG.a + 10
  CFG.c = CFG.b + CFG.c
}
main := fn() -> u64 {
  tick()
  tick()
  CFG.a + CFG.c + 14
}
