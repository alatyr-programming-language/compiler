## e2e — §2 OPERATOR OVERLOADING for a USER type. `Money` is a 1-word newtype struct; `@inline +`
## over `Money` is a user library operator. `p + q` in `main` routes (via `operator_decl_idx`)
## through that `@inline` fn — inlined at the site (`emit_inline_binop`), NOT the built-in scalar
## add — and its body `a.cents + b.cents` sums the fields. 40 + 2 -> 42.
Money := struct { cents : u64 }
@inline + := fn(a : Money, b : Money) -> u64 {
  a.cents + b.cents
}
main := fn() -> u64 {
  p := Money(cents = 40)
  q := Money(cents = 2)
  p + q
}
