## e2e (a call-binding followed by a `(`-prefixed trailing expression). `q := f(9)` then a bare
## `(expr)` line (no `return`) SILENTLY MISCOMPILED: `is_generic_inst` treated `f(9)(expr)` as a
## generic instantiation `f(9)` (erased type-args) + `(expr)` (the call args), dropping the `9` and
## the real args (e.g. `q := f(q+32)` — a garbage self-reference). A generic type-arg list holds
## TYPES, never a numeric/float/str LITERAL, so `is_generic_inst` now rejects a literal first arg →
## `f(9)` parses as an ordinary call and the `(expr)` is the separate trailing return. This also fixed
## the grouped-expression SIGFPE over several aggregate-returning-call bindings (structs + tuples).
f := fn(x : u64) -> u64 { return x + 1 }
Pair := struct { a : u64, b : u64 }
mkp := fn() -> Pair { return Pair(a = 40, b = 2) }
dm := fn(a : u64, b : u64) -> Pair { return Pair(a = a / b, b = a % b) }
main := fn() -> u64 {
  q := f(9)                 ## 10
  p := mkp()                ## (40, 2)
  r := dm(43, 10)           ## (4, 3)
  ## a `(`-prefixed grouped trailing expression (no `return`) over aggregate-call bindings
  (q + 32) + (p.a + p.b - 42) + (r.a + r.b - 7)   ## 42 + 0 + 0 = 42
}
