## sema/§ limits (I5/I9, FND-10 / STD-1): a `@limits(no_alloc)` translation unit must not call the
## allocation surface — a direct `allocate(…)` (tail-name matched, incl. through `?`) in a fn body
## violates the contract → REJECT.
@limits(no_alloc)
allocate := fn(n : u64) -> u64 { return n }
f := fn() -> u64 { x := allocate(42)
  return x }
main := fn() -> u64 { return f() }
