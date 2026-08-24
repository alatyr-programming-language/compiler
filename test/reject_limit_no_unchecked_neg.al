## FND-10 / I5+I9: an explicit unchecked around unary negation remains forbidden.
@limits(no_unchecked)
neg := fn(x : u64) -> u64 { return unchecked -x }
main := fn() -> u64 { return neg(0) }
