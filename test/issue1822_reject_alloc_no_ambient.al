## #1822 / Functions §2.3, §5.5 step (4), Memory §5.2.1: a STATEMENT call that omits its allocator
## parameter, with no `alloc::with` around it and no allocator parameter in the caller, has nothing to
## fill that parameter: a compile error that names the allocator. The checker used to accept it, and
## `take` read `ar` and `x` from stray registers (#1239).
take := fn(ar : ptr(mut Arena), x : u64) -> u64 { x + 1 }
main := fn() -> u64 {
  take(41)
  return 42
}
## expect: reject "leaves parameter `ar` unbound: an allocator parameter" "at line 7"
