## e2e REJECT (check) — an ill-typed DIRECT call NESTED inside a UFCS call's argument list:
## `v.bump(bump(v, "nope"))`. The whole argument SUBTREE under the mis-parsed `EnumLit` went unvisited by
## the conformance walk, so even the inner ordinary `Call` escaped — the hole was not limited to the UFCS
## node itself. The same expression spelled directly (`bump(v, bump(v, "nope"))`) was always rejected.
V := struct { n : u64 }

bump := fn(v : V, k : u64) -> u64 { v.n + k }

main := fn() -> u64 {
  v := V(n = 1)
  v.bump(bump(v, "nope"))
}
