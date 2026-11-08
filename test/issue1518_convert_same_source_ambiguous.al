## #1518, acceptance 3 — Types §4.6: "Two in-scope `@convert`s matching the same (source, target) at a
## site are an ambiguity error (no guessing, FND-3)". Asking the parameter does not dissolve this case:
## both conversions take a `u64` and return `P`, so `P(42)` stays refused.
P := struct { a : u64, b : u64 }
one := @convert fn(x : u64) -> P { return P(a = x, b = 0) }
two := @convert fn(y : u64) -> P { return P(a = 7, b = 0) }
main := fn() -> u64 {
  p := P(42)
  return p.a
}
## expect: reject "ambiguous @convert"
