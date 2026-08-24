## Orthogonal file limits compose: code using neither allocation nor OS facilities
## remains valid under both contracts and returns 42.
@limits(no_alloc, freestanding)
add_one := fn(x : u64) -> u64 { return x + 1 }
main := fn() -> u64 { return add_one(41) }
