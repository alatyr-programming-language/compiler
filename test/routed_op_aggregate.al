## e2e — routed OPERATOR-as-library (§2 / OP-1) over AGGREGATE operands that are NOT simple typed
## locals. Two front-end gaps this pins:
##   (a) a struct-LITERAL operand: `W(lo=..) + W(lo=..)` — the route must type the `StructLit` operand
##       to its struct name and fire the user `@inline +` (else the built-in scalar op runs over the
##       struct words → SIGILL).
##   (b) an aggregate-PARAMETER operand INSIDE a loop, with NO copy-to-local workaround: `acc + step`
##       where `step` is a `W` PARAM. Before the fix this SILENTLY evaluated the operator as a no-op
##       (the accumulation stayed 0) — a silent miscompile.
## 42 = (a) 16 + (b) 26.
W := struct { lo : u64, hi : u64 }
@inline + := fn(a : W, b : W) -> W {
  W(lo = unchecked { a.lo + b.lo }, hi = unchecked { a.hi + b.hi })
}

## (b) `step` is an aggregate PARAM; it is added into `acc` inside the loop WITHOUT being copied to a
## local first. `step + acc` puts the PARAM on the LEFT so the route must type the param operand.
accumulate := fn(step : W, n : u64) -> W {
  mut acc := W(lo = 0, hi = 0)
  mut i : u64 = 0
  while i < n {
    acc = step + acc
    i = unchecked { i + 1 }
  }
  acc
}

main := fn() -> u64 {
  ## (a) struct-LITERAL operands directly
  s := W(lo = 10, hi = 0) + W(lo = 6, hi = 0)

  step := W(lo = 2, hi = 0)
  t := accumulate(step, 13)

  s.lo + t.lo
}
