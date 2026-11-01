## FND-10 / I5+I9: ordinary checked unary negation is legal under no_unchecked.
## Unary `-x` is the plain subtraction `0 - x` (#1049); it carries no `unchecked`, so it is no escape.
@limits(no_unchecked)
neg := fn(x : u64) -> u64 { return -x }
main := fn() -> u64 { return neg(0) + 42 }
## expect: run 42
