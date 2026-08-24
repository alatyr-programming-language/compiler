## e2e REJECT (check) — the RECEIVER itself is an unbound name: `qqq.bump(1)` with no `qqq` in scope.
## In the `EnumLit` mis-parse the receiver span was read as the ENUM TYPE name, so it was never resolved
## as a value at all; the direct `bump(qqq, 1)` was correctly rejected. Locks that the receiver is now an
## ordinary argument-0 expression subject to ordinary name resolution.
V := struct { n : u64 }

bump := fn(v : V, k : u64) -> u64 { v.n + k }

main := fn() -> u64 {
  qqq.bump(1)
}
