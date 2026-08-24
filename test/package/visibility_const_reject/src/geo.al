## `PRIV_C` is a NON-`pub` comptime constant (a constant is a `comptime` binding — there is no `const`).
PRIV_C := 42
pub keep := fn() -> u64 { PRIV_C }
