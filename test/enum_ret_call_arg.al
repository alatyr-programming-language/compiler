## e2e — an ENUM-returning call passed DIRECTLY as an argument (`use(mk(...))`), the enum dual of a
## struct-returning call arg. Previously the call fell to the scalar path and only word 0 (the enum
## discriminant) reached the by-ref enum param — the payload came back garbage / crashed; the workaround
## was to bind the result to a local first. Now emit_arg materializes the enum return (disc + payload)
## into an agg-temp and passes it by reference. Returns 42 iff both the Some payload and the None arm
## survive the direct-arg pass.
mk := fn(x : u64) -> Option(u64) {
  if x > 0 { Option(u64).Some(x) } else { Option(u64).None }
}

unwrap_or := fn(o : Option(u64), dflt : u64) -> u64 {
  match o {
    Option::Some(v) => { v }
    Option::None => { dflt }
  }
}

main := fn() -> u64 {
  a := unwrap_or(mk(42), 0)     ## Some(42) passed directly -> 42
  b := unwrap_or(mk(0), 7)      ## None passed directly -> 7 (default)
  if a == 42 and b == 7 { return 42 }
  return 9
}
