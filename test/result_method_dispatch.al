## e2e — shared-name base methods (`unwrap`/`unwrap_or`/`expect`/`is_ok`/`is_err`) dispatch to
## `base/result.al` (NOT the same-name `base/option.al` sibling) when the receiver is a `Result`
## (spec FN-7: resolution keyed on the receiver). A bare/UFCS Result method used to resolve to the
## last-declared same-name generic (Option) and see `Ok`'s disc 0 as `None`. Returns 42 iff all correct.
main := fn() -> u64 {
  ok : Result(u64, u64) = Result.Ok(40)
  er : Result(u64, u64) = Result.Err(5)
  mut a : u64 = ok.unwrap()          ## 40 (was: panic "Option::unwrap on a None")
  a = a + er.unwrap_or(1)            ## + 1  = 41 (Err -> default)
  if ok.is_ok() { a = a + 1 }        ## + 1  = 42 (was: SIGILL at compile)
  if er.is_ok() { a = a + 100 }      ## Err.is_ok() = false
  if ok.is_err() { a = a + 100 }     ## Ok.is_err()  = false
  b := ok.expect("unreachable")      ## 40
  if unchecked (b != 40) { a = 0 }
  return a
}
