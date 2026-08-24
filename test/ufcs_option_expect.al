## UFCS method calls on a GENERIC `Option(V)` receiver (`o.expect(msg)` / `o.unwrap()`) must map the
## receiver to `self` and infer the leading type-arg from it — the same result the EXPLICIT call gives.
## A `Result(_, _)` `.expect()` guards the two-type-param path (must stay correct). Returns 42 iff all
## three unwrap correctly.
mkopt := fn(V : type, x : V) -> Option(V) { Option(V).Some(x) }
mkok := fn(T : type, E : type, x : T) -> Result(T, E) { Result(T, E).Ok(x) }

main := fn() -> u64 {
  o1 := mkopt(u64, 35)
  a := o1.expect("opt-expect boom")        ## Option.expect on a generic receiver -> 35
  o2 := mkopt(u64, 7)
  b := o2.unwrap()                          ## Option.unwrap on a generic receiver -> 7
  c := mkok(u64, bool, 100).expect("res")   ## Result.expect (guard the working two-type-param path)
  mut acc := unchecked (a + b)              ## 42
  if unchecked (c != 100) { acc = 0 }
  return unchecked acc
}
