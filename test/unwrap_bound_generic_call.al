## e2e — `.unwrap()` / `.expect()` / `.ok()` on a receiver BOUND FROM a generic-returning CALL
## (`m := parse(x); m.unwrap()`). The bound local's type is recovered from the callee's CONCRETE return
## enum (`block_decl_type` call-RHS typing → `Result(u64, u64)`), so the implicit-UFCS receiver-keyed
## resolution recovers each method's type-args (`unwrap(T, E, self)`, `ok(T, E, self)`). Was fail-loud
## (a call-RHS receiver's type-args weren't tracked). Returns 42.
mkR := fn(x : u64) -> Result(u64, u64) { return Result.Ok(x) }
mkE := fn(x : u64) -> Result(u64, u64) { return Result.Err(x) }

main := fn() -> u64 {
  a := mkR(20)
  b := mkR(9)
  c := mkE(0)
  mut r : u64 = 0
  r = r + a.unwrap()                                                                 ## +20 (Ok)
  r = r + b.expect("unexpected Err")                                                 ## +9  (Ok)
  match c.ok() { Option::Some(v) => { r = r + 500 } Option::None => { r = r + 13 } } ## +13 (Err -> None)
  ## 20 + 9 + 13 = 42
  if r == 42 { return 42 }
  1
}
