## build_reject — Stdlib §2.6: ORDERING (`<` `>` `<=` `>=`) over a `Slice(T)` view must FAIL LOUD.
##
## What was silently wrong: the pair fell to the scalar `cmpq`, so `a < b` answered on the two views'
## DATA POINTERS — a frame-layout accident, not a lexicographic order. Here `xs` sorts BEFORE `ys`
## element-wise, so `a < b` is TRUE and the correct exit is 1; the pre-fix compiler read `a < b` as
## FALSE (because `xs`'s data pointer is the higher address) and exited 42 — a normal exit with a
## wrong answer, the one forbidden outcome.
##
## Lexicographic order needs each ELEMENT's proven signedness to pick its setcc, and a runtime-len
## slice records only the element KIND, not its type — so failing loud is the correct interim answer.
main := fn() -> u64 {
  xs : [u64; 3] = [1, 2, 3]
  ys : [u64; 3] = [1, 2, 4]
  a := xs[0..3]
  b := ys[0..3]
  if a < b { return 1 }
  return 42
}
