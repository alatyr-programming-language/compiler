## build_reject — Stdlib §2.6: a bare `==` / `!=` over a FLOAT-element `Slice(f64)` view must FAIL
## LOUD, not compare the views' data pointers and not compare their raw IEEE-754 bits.
##
## What was silently wrong: the pair fell to the scalar `cmpq` and compared WORD 0 — the DATA
## POINTER — so these two views over EQUAL contents at different addresses read UNEQUAL and the
## program returned 42 by accident rather than by reasoning.
##
## Word-wise equality is not the answer for a float element either: a bit compare says `NaN == NaN`
## is TRUE (IEEE requires FALSE) and `0.0 == -0.0` is FALSE (IEEE requires TRUE). Comparing the
## elements explicitly (through the `f64` compare, which the `ucomisd` path answers correctly) is the
## documented workaround.
main := fn() -> u64 {
  xs : [f64; 3] = [1.0, 2.0, 3.0]
  ys : [f64; 3] = [1.0, 2.0, 3.0]
  a := xs[0..3]
  b := ys[0..3]
  if a == b { return 1 }
  return 42
}
