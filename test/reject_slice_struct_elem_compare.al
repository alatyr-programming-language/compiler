## build_reject — Stdlib §2.6: a bare `==` / `!=` over a STRUCT-element `Slice(P)` view must FAIL
## LOUD, not compare the views' data pointers.
##
## What was silently wrong: the pair fell to the scalar `cmpq` and compared WORD 0 — the DATA
## POINTER — so these two views over EQUAL contents at different addresses read UNEQUAL.
##
## A struct / enum / `str` / pointer element is multi-word, and its padding and unused payload words
## are indeterminate, so the word-wise content compare that answers a scalar-element slice is not
## correct here: such an element needs `base::derive::eq` per element. The same fail-loud also
## catches a slice paired with a NON-slice operand (an array, a `str`, a scalar), which silently
## compared two unrelated words.
P := struct { x : u64, y : u64 }
main := fn() -> u64 {
  ps := [P(x = 1, y = 2), P(x = 3, y = 4)]
  qs := [P(x = 1, y = 2), P(x = 3, y = 4)]
  a := ps[0..2]
  b := qs[0..2]
  if a == b { return 1 }
  return 42
}
