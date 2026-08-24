## sema/§ limits: a `@limits(no_alloc)` unit that never calls `allocate` ACCEPTS + builds + runs. 42.
@limits(no_alloc)
g := fn(x : u64, y : u64) -> u64 { return x + y }
main := fn() -> u64 { return g(40, 2) }
