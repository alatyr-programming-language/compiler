## e2e/fmt — the `comptime N : u64` COMPTIME VALUE PARAMETER (Comptime §10 `comptime-param`) survives
## a reformat. The parser CONSUMES the keyword (`p_params`, `saw_ct`) and the `Param` node records
## only the name and type spans, so fmt dropped it and `fn(comptime N : u64, …)` came back with a
## RUNTIME `N`. A different declaration: the type function no longer folds `[u64; N/64]` and the
## operator no longer routes by binding `N` from its operand — `uint_generic_op` ran 42 before a
## reformat and SIGILL'd (132) after.
##
## Pinned alongside the OTHER parameter modifiers (`in`, `out`, `in out`), which were already
## recovered, so a change to one modifier's scan cannot quietly take the others with it.
## (A `comptime` value parameter is accepted only on a type function or a glyph-named operator in
## this slice, so those are the two shapes exercised.)
Bag := struct { a : u64, b : u64 }

## a type FUNCTION over a comptime value parameter — the width folds into the array length
w := fn(comptime N : u64) -> type { struct { words : [u64; N / 64] } }

## a glyph-named OPERATOR over a comptime value parameter — routes by binding `N` from the operand
@inline + := fn(comptime N : u64, a : w(N), b : w(N)) -> w(N) {
  mut r : w(N) = a
  comptime for i in 0 .. N / 64 {
    r.words[i] = unchecked { a.words[i] + b.words[i] }
  }
  return r
}

## the three by-reference modifiers, unchanged by this fix but locked here too
bump := fn(in out b : Bag) {
  b.a = b.a + 1
}
seed := fn(out b : Bag) {
  b.a = 5
}
peek := fn(in b : Bag) -> u64 {
  return b.b
}

main := fn() -> u64 {
  x := w(128)(words = [30, 5]) + w(128)(words = [4, 1])
  if x.words[0] != 34 { return 1 }
  if x.words[1] != 6 { return 2 }
  mut g := Bag(a = 0, b = 7)
  bump(g)
  if g.a != 1 { return 3 }
  seed(g)
  if g.a != 5 { return 4 }
  if peek(g) != 7 { return 5 }
  return 42
}
