## e2e — `Result::map` / `Result::map_err` / `Result::and_then` via IMPLICIT UFCS `r.map(f)` (Stdlib
## §160). A 3-type-parameter generic reached WITHOUT explicit type-args: T/E come from the receiver's
## declared type (`Result(u64, u64)`), and the 3rd type-param (`U`/`F` — the mapper's return, absent from
## the receiver) is recovered from the fn ARGUMENT's declared return type. The explicit-type-arg form
## (`map(T, E, U, r, f)`) stays available (see result_map.al / result_and_then.al). Returns 42.
step := fn(x : u64) -> u64 { return x + 1 }
chk := fn(x : u64) -> Result(u64, u64) {
  if x > 100 { return Result(u64, u64).Err(9) }
  return Result(u64, u64).Ok(x + 1)
}

main := fn() -> u64 {
  ro : Result(u64, u64) = Result.Ok(41)
  re : Result(u64, u64) = Result.Err(7)
  mut a : u64 = 0
  mut b : u64 = 0
  mut c : u64 = 0
  mut d : u64 = 0

  ## map — Ok(41) → Ok(42)
  rm := ro.map(step)
  match rm { Result::Ok(v) => { a = v } Result::Err(e) => { a = 500 } }

  ## map — Err(7) unchanged (f not applied)
  rme := re.map(step)
  match rme { Result::Ok(v) => { b = 500 } Result::Err(e) => { b = e } }

  ## map_err — Err(7) → Err(8)
  rmerr := re.map_err(step)
  match rmerr { Result::Ok(v) => { c = 500 } Result::Err(e) => { c = e } }

  ## and_then — Ok(41) → chk → Ok(42)
  rat := ro.and_then(chk)
  match rat { Result::Ok(v) => { d = v } Result::Err(e) => { d = 500 } }

  if a == 42 and b == 7 and c == 8 and d == 42 { return 42 }
  1
}
