## e2e — WHOLE-VALUE assignment to a mutable multi-word STRUCT global (`G = R(…)`, a struct LITERAL
## RHS). The bare-name global-write path stored a SINGLE word (correct for a scalar global) — for an
## aggregate global it dropped every word past word 0, and even word 0 was an ADDRESS not a value (a
## §Priority-1 silent miscompile). Now `emit_mut_global_whole_assign` copies ALL words to `.data`
## ascending. Init (7,8,9); after `G = R(12,20,10)` every word survives: 12 + 20 + 10 = 42.
## src/ + lib/ whole-assign only SCALAR globals, so this stays fixpoint-neutral.
R := struct { a : u64, b : u64, c : u64 }
mut G := R(a = 7, b = 8, c = 9)
main := fn() -> u64 {
  G = R(a = 12, b = 20, c = 10)
  G.a + G.b + G.c
}
