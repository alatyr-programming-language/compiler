## FN-6 §6.2 — a CAPTURING closure through a generic HOF `twice` that is called at TWO sites: once
## with a capturing closure `f` (captures `c`), once with a NON-capturing top-level fn `inc`. This is
## the MULTI-call-site generalization: specializing `twice` IN PLACE would break the non-capturing
## site (it would see the widened arity), so the driver deep-CLONES `twice` for the capturing site
## only — the clone `__hoflam<fnpos>` threads f's capture `c` (`g(x) -> g(x, c)`), the original
## `twice` stays intact for the `inc` site. The clone STAYS GENERIC and monomorphizes over T=u64.
## c := 1: twice(clone) = (10+1)+(10+1) = 22; twice(orig, inc) = (9+1)+(9+1) = 20; 22+20 = 42.
twice := fn(T : type, g : T, x : T) -> T { return g(x) + g(x) }
inc := fn(n : u64) -> u64 { return n + 1 }
main := fn() -> u64 {
  c := 1
  f := fn(n : u64) -> u64 { return n + c }
  a := twice(u64, f, 10)
  b := twice(u64, inc, 9)
  u64(a + b)
}
