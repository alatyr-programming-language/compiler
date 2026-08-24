## e2e REJECT (check) — the OVER-arity twin: `v.bump(1, 2, 3)` passes four arguments (receiver + 3) to
## the two-parameter `bump`. Same root as `reject_ufcs_arity_under`.
V := struct { n : u64 }

bump := fn(v : V, k : u64) -> u64 { v.n + k }

main := fn() -> u64 {
  v := V(n = 1)
  v.bump(1, 2, 3)
}
