## FN-6 regression: a module-qualified top-level function used as a function value
## must pass its code address, not fall through to a frame-slot read.
add1 := fn(x : u64) -> u64 { x + 1 }

apply := fn(f : fn(u64) -> u64, x : u64) -> u64 { f(x) }

main := fn() -> u64 {
  apply(main::add1, 41)
}
