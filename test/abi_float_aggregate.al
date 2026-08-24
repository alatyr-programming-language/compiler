## e2e (x86_64): float-BEARING AGGREGATES passed / returned BY VALUE. The compiler's internal
## aggregate ABI passes a struct/tuple by REFERENCE (a pointer to a materialized block) and returns
## it via the multi-GPR convention — both float-CLASS-agnostic, so a float field's IEEE-754 bits
## round-trip through memory / a GPR unchanged. What this test locks in is that a float field/element
## reached through such an aggregate READS + ARITHMETICS on the xmm (float) path, not the integer one.
##
## Covers:
##   sum_struct(Pt{f64,f64})        struct PARAM by value, float field read + `addsd`
##   mk_struct() -> Pt              struct RETURN by value, float fields delivered + received
##   sum_tuple((f64,f64))           uniform float-TUPLE param (bound as a pmode-1 array of f64 → eek 9)
##   sum_mixed((u64,f64))           MIXED int/float tuple param (per-component eek from the tcomps table)
## Expected process exit: 42.
##   sum_struct(Pt(20.0, 22.0)) = 42.0 -> 42     ... but we spread the 42 across the four calls:
Pt := struct { x : f64, y : f64 }

sum_struct := fn(p : Pt) -> f64 {
  return p.x + p.y
}

mk_struct := fn() -> Pt {
  return Pt(x = 5.0, y = 6.0)
}

sum_tuple := fn(t : (f64, f64)) -> f64 {
  return t.0 + t.1
}

sum_mixed := fn(t : (u64, f64)) -> u64 {
  return t.0 + u64(t.1)
}

main := fn() -> u64 {
  ## struct param by value: 10.0 + 4.0 = 14.0 -> 14
  a := u64(sum_struct(Pt(x = 10.0, y = 4.0)))
  ## struct return by value: (5.0 + 6.0) = 11.0 -> 11
  r := mk_struct()
  b := u64(r.x + r.y)
  ## uniform float tuple param: 7.0 + 3.0 = 10.0 -> 10
  c := u64(sum_tuple((7.0, 3.0)))
  ## mixed (u64, f64) tuple param: 5 + u64(2.0) = 7
  d := sum_mixed((5, 2.0))
  return a + b + c + d   ## 14 + 11 + 10 + 7 = 42
}
