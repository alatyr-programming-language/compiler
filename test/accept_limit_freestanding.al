## sema/§ limits: a `@limits(freestanding)` unit that makes no syscall ACCEPTS + builds + runs. 42.
@limits(freestanding)
g := fn(x : u64, y : u64) -> u64 { return x + y }
main := fn() -> u64 { return g(40, 2) }
