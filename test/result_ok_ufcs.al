## e2e — `Result::ok()` via UFCS (Stdlib §160): `Ok(v)` → `Some(v)`, `Err(e)` → `None`. A 2-type-param
## method (`ok(T, E, self : Result(T, E)) -> Option(T)`) whose BOTH type-args are inferred from the
## receiver's declared type (spec FN-7 receiver-keyed resolution). Returns 42 iff both map correctly.
main := fn() -> u64 {
  r1 : Result(u64, u64) = Result.Ok(42)
  r2 : Result(u64, u64) = Result.Err(9)
  a := r1.ok()                                  ## Some(42)
  b := r2.ok()                                  ## None
  return unchecked (a.unwrap() + b.unwrap_or(0))   ## 42 + 0 = 42
}
