## sema/§ limits (I5/I9, FND-10): a translation unit declaring `@limits(no_unchecked)` must NOT use an
## `unchecked` scope — an `unchecked <expr>` opts out of I11 verification, so it violates the unit's
## contract → REJECT. The scan is DEEP: the `unchecked` is nested inside a returned arithmetic expression.
@limits(no_unchecked)
f := fn(a : u64, b : u64) -> u64 {
  return unchecked (a + b)
}
main := fn() -> u64 { return f(40, 2) }
