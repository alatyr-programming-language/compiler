## e2e (Types §9.4 / the enum return convention) — a TAIL VALUE-`match` whose scrutinee is a CALL, with
## NO intervening binding: `main := fn() -> u64 { match mkn(10) { N::Two(a, b) => … } }`. The callee
## delivers its enum in the return registers (word 0 = disc/%rax, payload word i = %rdx/%rcx/…), and the
## tail value-match must stage EVERY returned word into the match scratch before dispatching.
##
## Was a SILENT MISCOMPILE: that path stored only TWO words (disc/%rax + payload[0]/%rdx), so the SECOND
## and later payload words were dropped — `N.Two(10, 11)` bound to `(a, b)` yielded a = 10, b = 0 and the
## fn returned 10 instead of 21 (a normal exit with a wrong value). The statement-match spelling
## (`match mkn(10) { N::Two(a, b) => { return a + b } }`) already staged all words, so the defect was
## confined to the value-match — which is exactly the spelling with no local to inspect.
##
## Both a 2-word and a 3-word payload are exercised, and every payload component carries a DISTINCT
## value that the arm reads, so a dropped, zeroed or swapped word changes the answer:
##   two(10)   = 10 + 11              = 21
##   three(4)  = 4 + 20 + 5           = 29
## → 21 + 29 = 50. NB the result MUST stay < 126 (the WASM sweep's WASI `proc_exit` only accepts [0,126)).
N := enum { One(u64), Two(u64, u64), Three(u64, u64, u64) }

mk2 := fn(x : u64) -> N {
  return N.Two(x, 11)
}
mk3 := fn(x : u64) -> N {
  return N.Three(x, 20, 5)
}

two := fn(x : u64) -> u64 {
  match mk2(x) {
    N::Two(a, b) => (a + b)
    N::Three(a, b, c) => 0
    N::One(a) => a
  }
}
three := fn(x : u64) -> u64 {
  match mk3(x) {
    N::Three(a, b, c) => (a + b + c)
    N::Two(a, b) => 0
    N::One(a) => a
  }
}

main := fn() -> u64 {
  return two(10) + three(4)
}
