## e2e (Types §9.4 return ABI) — `match <WIDE-enum-returning call>` with NO intervening binding, in both
## the STATEMENT spelling (braced arms with `return`) and the TAIL VALUE spelling (bare arm values). The
## callee's {disc, payload…} block is 11 words (> the 7-word register-return budget), so it delivers
## through the hidden result POINTER and has NO return registers at all.
##
## Was a RAW SEGFAULT (exit 139): the match-scrutinee staging wired no hidden pointer and then read
## %rax..%r11 for a value that never rode them, so the callee wrote its 11 words through whatever %rdi
## happened to hold. Now the match scratch block's word-0 ADDRESS is handed down as that hidden pointer
## (the scratch is already `1 + max-enum-arity` words wide), so the callee writes the whole block straight
## into the scratch and nothing is copied back — the same wiring a `t := mk(…)` binding uses.
##
## Every payload word carries a DISTINCT value (base+0 .. base+9) and each arm reads the FIRST (a), a
## MIDDLE (e), the LAST (j) and an interior pair (h - b), so a dropped, zeroed or swapped word changes the
## answer: (1 + 5 + 10) + (8 - 2) = 22 per spelling; the value spelling subtracts 12 so the two
## spellings contribute DISTINCT amounts (a single working spelling can't fake the total): 22 + 10 = 32.
## NB the result MUST stay < 126 (the WASM sweep's WASI `proc_exit` only accepts [0,126)).
W := enum { Many(u64, u64, u64, u64, u64, u64, u64, u64, u64, u64), Small(u64) }

mk := fn(base : u64) -> W {
  return W.Many(base, base + 1, base + 2, base + 3, base + 4, base + 5, base + 6, base + 7, base + 8, base + 9)
}

## STATEMENT spelling: braced arms, each with an explicit `return`.
stmt := fn(base : u64) -> u64 {
  match mk(base) {
    W::Many(a, b, c, d, e, f, g, h, i, j) => { return (a + e + j) + (h - b) }
    W::Small(x) => { return 0 }
  }
}

## TAIL VALUE spelling: bare arm values, the match IS the fn's result.
val := fn(base : u64) -> u64 {
  match mk(base) {
    W::Many(a, b, c, d, e, f, g, h, i, j) => ((a + e + j) + (h - b)) - 12
    W::Small(x) => 0
  }
}

main := fn() -> u64 {
  return stmt(1) + val(1)
}
