## FND-10 / I5+I9: ordinary checked unary negation is legal under no_unchecked.
## The parser's internal Expr::Unchecked marker must not turn this source-level `-x` into an escape.
@limits(no_unchecked)
neg := fn(x : u64) -> u64 { return -x }
main := fn() -> u64 { return neg(0) + 42 }
