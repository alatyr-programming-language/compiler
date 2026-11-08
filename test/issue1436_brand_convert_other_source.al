## Issue #364 / #1436 — a brand whose only in-scope `@convert` takes ANOTHER source type keeps the brand
## crossing for an operand that conversion does not accept.
##
## Types §4.6 (v1.8.0, l.332-338): step (2) is "the **one** in-scope `@convert` whose return type is `T`
## and whose parameter **accepts** `typeof(v)`"; "otherwise (3) a builtin lattice conversion (§4.2)", and
## for a branded target "An in-scope `@convert` therefore precedes the brand crossing" only "where a
## conversion matches". `from_bool` does not accept the literal `42`, which is inferred from context
## (§9.1) and no `bool` represents, so `Flag(42)` is the crossing and answers 42; `Flag(true)` runs
## `from_bool` and answers 1.
##
## Once #364's brand rule let a brand reach step (2) without asking the parameter, `Flag(42)` ran
## `from_bool` with an integer operand.
Flag := brand(u64)

from_bool := @convert fn(b : bool) -> Flag {
  if b { return Flag(1) }
  Flag(0)
}

main := fn() -> u64 {
  t := Flag(true)
  if u64(t) != 1 { return 1 }
  f := Flag(42)
  u64(f)
}
## expect: run 42
