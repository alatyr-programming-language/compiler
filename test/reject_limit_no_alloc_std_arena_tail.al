## A direct standard allocation in a function's trailing expression is still a
## no_alloc violation; the contract must not depend on statement-vs-tail form.
@limits(no_alloc)
make := fn() { std::os::arena(4096) }
main := fn() -> u64 { 42 }
