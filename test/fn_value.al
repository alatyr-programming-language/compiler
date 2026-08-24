## e2e (fn-VALUES: a function used as a value + an indirect call). `apply(add1, 41)` passes the
## function `add1` as a value (its code pointer, `leaq add1(%rip)`) to `apply`, which calls it
## indirectly through its fn-value param (`f(v)` → `call *(f's slot)`). DCE also keeps `add1`
## reachable (it is referenced as a value, not called by name). Enables the higher-order stdlib
## (map/filter/reduce/sort_by over a fn-value predicate). `add1(41)` = 42.
add1 := fn(x : usize) -> usize { return x + 1 }
apply := fn(f : fn(x : usize) -> usize, v : usize) -> usize { return f(v) }
main := fn() -> u64 {
  u64(apply(add1, 41))
}
