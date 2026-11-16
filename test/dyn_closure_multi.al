## FN-11 multi-capture — a `dyn fn(u64)->u64` erased over a lambda that captures TWO values.
## `s` captures `a` and `b`; `dyn_over(ptr(mut s))` builds the {code, env} fat pair whose env holds
## BOTH captures. The synthesized adapter shifts the user arg down one register and appends both
## captures (env words 0/1) before tail-jumping to the lifted body `x + a + b`.
##   a = 10, b = 20 ;  d(12) = 12 + 10 + 20 = 42
## #1663: the closure storage is declared `mut` because `dyn_over(ptr(mut store))` takes a WRITABLE
## address (Memory §4.4: an immutable place yields only `ptr(T)`); the spec's own §6.3 spelling is
## `ptr(mut store)` over a named place, and the place here is named by these bindings. Behaviour unchanged.
main := fn() -> u64 {
  a := 10
  b := 20
  mut s := fn(x : u64) -> u64 { return x + a + b }
  d : dyn fn(u64) -> u64 = dyn_over(ptr(mut s))
  return d(12)
}
## expect(x86_64): run 42
