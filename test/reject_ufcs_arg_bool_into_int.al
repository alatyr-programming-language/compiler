## e2e REJECT (check) — the BOOL row of the same UFCS argument-conformance hole: `v.bump(true)` into
## `k : u64`. `true` has no conforming reading as an integer (Types §3.1/§4.2), exactly as the direct
## `bump(v, true)` is rejected. Escaped `check` entirely while a UFCS call parsed as an `EnumLit`.
V := struct { n : u64 }

bump := fn(v : V, k : u64) -> u64 { v.n + k }

main := fn() -> u64 {
  v := V(n = 1)
  v.bump(true)
}
