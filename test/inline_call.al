## e2e — `@inline` call-site expansion (§3.1/§3.5), the foundation for operators-as-library (§2). A call
## to an `@inline` fn with a TAIL-EXPRESSION body is EXPANDED in place (no `call`): each arg is bound
## into an inline-scratch slot, the params are aliased to those slots, and the body is emitted inline.
## Args are evaluated to the stack first (then popped in reverse) so a nested `@inline` in a later arg
## can't clobber an earlier one. add(dbl(19), dbl(2)) = (19+19) + (2+2) = 38 + 4 = 42.
@inline add := fn(a : u64, b : u64) -> u64 { a + b }
@inline dbl := fn(x : u64) -> u64 { x + x }
main := fn() -> u64 {
  add(dbl(19), dbl(2))
}
