## e2e build_reject — `.unwrap()` on a receiver BOUND FROM A PARAM-LADEN generic call
## (`m2 := r.map(inc); m2.unwrap()`). `r.map(inc)` returns `Result(U, E)` whose `U`/`E` are the callee's
## OWN type-PARAMETERS, so the bound local `m2`'s type must be SUBSTITUTED (`U = inc's return`, `E = r's
## E`). The SLOT path substitutes it (so `match m2 { … }` and the explicit `unwrap(u64, u64, m2)` both
## work), but the implicit-UFCS receiver-typing resolver (`block_decl_type` → source scan) cannot: the
## only substitution helper (`subst_enum_ret_span`) resolves its receiver via `recv_full_emit`/`EMIT_BODY`,
## which is invalid in the mono PRE-PASS where `m2.unwrap()`'s instance must be minted (no slot map, stale
## `EMIT_BODY`). So this FAILS LOUD (a clear `selfhost:` panic) rather than emit an undefined-symbol call.
## Workarounds: `match m2 { Result::Ok(v) => … }` or the explicit `unwrap(u64, u64, m2)`.
inc := fn(x : u64) -> u64 { return x + 1 }

main := fn() -> u64 {
  r : Result(u64, u64) = Result.Ok(41)
  m2 := r.map(inc)
  return m2.unwrap()
}
