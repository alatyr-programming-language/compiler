## e2e (aggregate produced by a `match` EXPRESSION delivered DIRECTLY as a call ARGUMENT). The `match`
## dual of `agg_from_branch_arg`: `f(match n { 1 => Rec(12,30) ; _ => … })` materializes each arm's
## struct into the agg-temp and passes its address by-ref (`emit_val_match_to_local` into the block).
## Was a scalar-default garbage-pointer pass → crash. `12 + 30` -> 42.
Rec := struct { a : i64, b : i64 }
f := fn(x : Rec) -> i64 { x.a + x.b }
main := fn() -> u64 {
  n := 1
  return u64(f(match n { 1 => Rec(a = 12, b = 30) ; _ => Rec(a = 0, b = 0) }))
}
