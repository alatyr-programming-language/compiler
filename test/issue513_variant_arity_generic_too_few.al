## Issue #513 / spec Types §9.4 — the rule reaches a GENERIC enum instance too, because it is judged on
## the same declaration walk the variant-NAME rule already uses (`Result(u64, u64).Zzz(3)` was already
## refused on the parent). `Result(u64, u64).Ok()` supplies nothing to a variant that carries one
## payload; the parent built it clean and ran to 0.
main := fn() -> u64 {
  v := Result(u64, u64).Ok()
  match v {
    Ok(x) => { return x }
    Err(e) => { return e + 1 }
  }
  0
}
