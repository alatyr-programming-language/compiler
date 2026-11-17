## FN-11 — `dyn_over(ptr(mut store))` over a store the program declared `mut` stays admissible. Functions
## §1.6 (spec#152): the address of `store` is an ordinary address-of, so Memory §4.4 decides the form —
## `ptr(mut store)` only over a writable place, `ptr(store)` over any. The canonical `dyn_over(ptr(store))`
## is `test/dyn_closure.al`; this is the other admissible spelling, kept so the `mut` form is still built
## and still formatted back with its qualifier.  d(12) = 12 + 30 = 42
## expect(x86_64): run 42
main := fn() -> u64 {
  a := 30
  mut s := fn(x : u64) -> u64 { return x + a }
  d : dyn fn(u64) -> u64 = dyn_over(ptr(mut s))
  return d(12)
}
