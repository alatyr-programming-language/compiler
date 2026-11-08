## Issue #364 / #1436 — two in-scope `@convert`s to one brand from DIFFERENT sources are not ambiguous:
## each operand selects the one whose parameter accepts it.
##
## Types §4.6 (v1.8.0): "A `@convert` is keyed by its (**source parameter type**, **return type**) … two
## conversions to the same target therefore coexist under distinct names" (l.359-363); only "Two in-scope
## `@convert`s matching the same (source, target) at a site are an **ambiguity error**" (l.371-372).
## Step (2) selects "the **one** … whose parameter **accepts** `typeof(v)`" (l.332-333).
##
## `from_u64` records that it ran, so the run says which conversion each site took:
##   `Flag(n)`, n : u64 — `from_u64` (sets SEEN), answers 42; `from_bool` does not accept a `u64`;
##   `Flag(true)`       — `from_bool`, answers 1; inside it `Flag(1)` is `from_u64` again (the other
##                        conversion; `from_bool` is not a candidate in its own body, §4.6 Termination).
## Inside `from_u64`, `Flag(n)` has no candidate left but `from_bool`, which does not accept a `u64`, so it
## is the brand crossing (Termination: "resolves at step (3) to the **brand** crossing").
Flag := brand(u64)

mut SEEN : u64 = 0

from_bool := @convert fn(b : bool) -> Flag {
  if b { return Flag(1) }
  Flag(0)
}

from_u64 := @convert fn(n : u64) -> Flag {
  SEEN = SEEN + 1
  Flag(n)
}

main := fn() -> u64 {
  n : u64 = 42
  f := Flag(n)
  if SEEN != 1 { return 1 }
  t := Flag(true)
  if u64(t) != 1 { return 2 }
  if SEEN != 2 { return 3 }
  u64(f)
}
## expect: run 42
