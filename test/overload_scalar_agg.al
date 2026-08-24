## ROADMAP §1 overload resolution: a scalar-literal call must NOT be spuriously rejected as a
## "unbound name" when a same-name overload takes an AGGREGATE parameter. sema does not resolve
## overloads, so its per-argument conformance check stays tolerant for an overload set — the scalar
## `10` must not be tag-compared against the sibling `g(A)`'s struct parameter (which flagged a false
## mismatch that surfaced as an unbound-name rejection). Both overloads are reachable; the genuine
## unbound-Var walk of each argument is unaffected. Real resolution happens later (lower / link).
A := struct { v : u64 }
g := fn(x : u64) -> u64 { return x + 100 }
g := fn(p : A) -> u64 { return p.v + 200 }
main := fn() -> u64 {
  x := g(10)          ## scalar literal → g(u64) → 110
  y := g(A(v = 2))    ## struct arg     → g(A)   → 202
  return y - x - 50   ## 202 - 110 - 50 = 42
}
