## sema/§ limits: a `@limits(no_unchecked)` unit that never uses an `unchecked` scope ACCEPTS + builds +
## runs. Ordinary checked arithmetic is fine — only the `unchecked` escape is forbidden. 42.
@limits(no_unchecked)
g := fn(x : u64, y : u64) -> u64 { return x + y }
main := fn() -> u64 { return g(40, 2) }
