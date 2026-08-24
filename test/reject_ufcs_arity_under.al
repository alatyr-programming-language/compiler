## e2e REJECT (check) — ARITY through a UFCS call: `v.bump()` supplies only the receiver for
## `bump(v : V, k : u64)`. The direct `bump(v)` has always been rejected; the UFCS spelling reached NO
## arity check at all, because the mis-parse produced an `EnumLit` (a variant construction, which has no
## arity contract) instead of a `Call`.
V := struct { n : u64 }

bump := fn(v : V, k : u64) -> u64 { v.n + k }

main := fn() -> u64 {
  v := V(n = 1)
  v.bump()
}
