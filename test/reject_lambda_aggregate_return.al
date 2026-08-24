## FN-6 first slice — a function VALUE (lambda) returning a MULTI-WORD aggregate (struct/enum/str) is
## not yet supported and MUST be rejected fail-loud, not silently miscompiled. A lambda is called only
## INDIRECTLY (through its code-pointer value), and the indirect-call site carries no signature for the
## fn value, so it captured only ONE result word (losing `y`) and could not resolve the result's fields
## — `r := mk(40); r.x + r.y` returned garbage (184, not 42). Scalar-returning lambdas are fine.
P := struct { x : u64, y : u64 }
main := fn() -> u64 {
  mk := fn(a : u64) -> P { return P(x = a, y = 2) }
  r := mk(40)
  return r.x + r.y
}
