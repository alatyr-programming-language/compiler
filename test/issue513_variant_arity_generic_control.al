## Issue #513 CONTROL — the GENERIC enum instances at their correct arity. `Result` and `Option` reach
## the same constructor path as a user enum (the reject row for `Result(u64, u64).Ok()` proves the rule
## sees them), so the prelude's own single-payload variants must keep building and running. Returns
## 20 + 22 = 42.
main := fn() -> u64 {
  r := Result(u64, u64).Ok(20)
  o := Option(u64).Some(22)
  mut t := 0
  match r {
    Ok(v) => { t = t + v }
    Err(e) => { t = t + e + 100 }
  }
  match o {
    Some(v) => { t = t + v }
    None => { t = t + 100 }
  }
  t
}
