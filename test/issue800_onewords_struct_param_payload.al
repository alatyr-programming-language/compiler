## Issue #800 — an enum or `Result` payload built from a ONE-word struct PARAMETER. A struct param is
## passed by reference: its slot holds a pointer to the caller's struct. A one-word struct payload is
## lowered as a scalar (its only word is the whole value), and the scalar read of the param pushed the
## POINTER instead of word 0. So each payload below carried a stack address, and on the parent this
## program built cleanly and exited 2 (the first check) instead of 42. Every form is covered: `Ok` and
## `Err` returned and matched, a user enum variant, `Option.Some`, the `?` binding, the payload stored
## into an enum LOCAL (the store path, not the return registers), and the argument passed as a named
## local rather than a literal. Each check has its own exit code, so a partial fix names the form.
S1 := struct { k1 : u64 }
E := enum { A(S1), N }
ok_of := fn(s : S1) -> Result(S1, u64) { return Result(S1, u64).Ok(s) }
err_of := fn(s : S1) -> Result(u64, S1) { return Result(u64, S1).Err(s) }
variant_of := fn(s : S1) -> E { return E.A(s) }
some_of := fn(s : S1) -> Option(S1) { return Option(S1).Some(s) }
stored := fn(s : S1) -> u64 {
  e : E = E.A(s)
  match e { E::A(q) => { q.k1 } E::N => { 0 } }
}
tried := fn() -> Result(u64, u64) {
  q := ok_of(S1(k1 = 6))?
  return Result(u64, u64).Ok(q.k1)
}
main := fn() -> u64 {
  if (match ok_of(S1(k1 = 5)) { Result::Ok(q) => { q.k1 } Result::Err(e) => { 0 } }) != 5 { return 2 }
  if (match err_of(S1(k1 = 7)) { Result::Ok(q) => { 0 } Result::Err(e) => { e.k1 } }) != 7 { return 3 }
  if (match variant_of(S1(k1 = 8)) { E::A(q) => { q.k1 } E::N => { 0 } }) != 8 { return 4 }
  if (match some_of(S1(k1 = 9)) { Option::Some(q) => { q.k1 } Option::None => { 0 } }) != 9 { return 5 }
  if stored(S1(k1 = 10)) != 10 { return 6 }
  if (match tried() { Result::Ok(v) => { v } Result::Err(e) => { 0 } }) != 6 { return 7 }
  arg : S1 = S1(k1 = 11)
  if (match ok_of(arg) { Result::Ok(q) => { q.k1 } Result::Err(e) => { 0 } }) != 11 { return 8 }
  42
}
