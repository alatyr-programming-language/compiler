## sema/§ limits: a `@limits(no_comptime)` unit with NO comptime construct ACCEPTS + builds + runs —
## the `@limits(...)` marker decl is lower-invisible (alias-shaped, emitted as nothing). Returns 42.
@limits(no_comptime)
add := fn(x : u64, y : u64) -> u64 { return x + y }
main := fn() -> u64 { return add(40, 2) }
