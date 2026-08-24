## e2e — Stdlib §2.6 / Types §6.4: a bare `==` / `!=` over two by-value TUPLE or fixed-ARRAY values
## compares them COMPONENTWISE, never word 0 alone and never the block ADDRESS.
##
## What was silently wrong: a tuple parses as an `ArrayLit`, so a tuple/array local has NO struct or
## enum decl and the bare-comparison guard (`agg_value_var_words`, which reads the slot KIND 2/3) saw
## 0 words for it. Both operands fell through to the scalar `cmpq`, which compared WORD 0 ONLY:
## `(5,7) == (5,9)` and `[5,7] == [5,9]` both read EQUAL. A tuple/array PARAM was worse — its slot
## holds the caller block's ADDRESS, so `p == q` compared two addresses and read two field-EQUAL
## tuples as UNEQUAL (the tuple twin of `agg_cmp_param_not_address`). Both were normal-exit wrong
## values, the one forbidden outcome.
##
## Covers: a word-1-only difference (the classic case), `!=`, two equal-valued blocks at DIFFERENT
## addresses, a 4-component block differing only in the LAST word (proves every word is compared),
## a by-ref TUPLE param, and a by-ref fixed-ARRAY param. 1 + 2 + 4 + 8 + 16 + 6 + 5 = 42.
##
## The wat / aarch64 / riscv64 backends reject a bare aggregate comparison loudly (they have no
## structural derive), so this fixture traps there — the same arrangement as `agg_cmp_not_address`.
tcmp := fn(p : (u64, u64), q : (u64, u64)) -> bool {
  return p == q
}
acmp := fn(p : [u64; 3], q : [u64; 3]) -> bool {
  return p != q
}
main := fn() -> u64 {
  a := (5, 7)
  b := (5, 9)             ## equal to `a` in word 0, differs in word 1
  c := (5, 7)             ## equal to `a` by VALUE, at a different address
  mut acc : u64 = 0
  if a == b { acc = acc + 100 } else { acc = acc + 1 }   ## word-1 difference seen  -> +1
  if a != b { acc = acc + 2 }                            ## `!=` is its negation    -> +2
  if a == c { acc = acc + 4 }                            ## value, not address      -> +4

  xs := [1, 2, 3, 9]
  ys := [1, 2, 3, 8]      ## differs in the LAST word only
  zs := [1, 2, 3, 9]
  if xs != ys { acc = acc + 8 }                          ## every word compared     -> +8
  if xs == zs { acc = acc + 16 }                         ## all four words equal    -> +16

  p : (u64, u64) = (5, 7)
  q : (u64, u64) = (5, 7)
  if tcmp(p, q) { acc = acc + 6 }                        ## by-ref tuple PARAMS     -> +6

  m : [u64; 3] = [1, 2, 3]
  n : [u64; 3] = [1, 2, 4]
  if acmp(m, n) { acc = acc + 5 }                        ## by-ref array PARAMS     -> +5
  return acc
}
