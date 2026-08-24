## P0 regression: a function named like a scalar conversion is resolved as the
## conversion builtin. A zero-argument call must be a located lower reject,
## rather than a null-argument dereference in arg_expr_at.
f32 := fn() -> u64 { return 1 }

main := fn() -> u64 { return f32() }
