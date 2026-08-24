## FN-11 escape check (Memory §5.3.1) — a `dyn` value BORROWS its `store`; it must not outlive it.
## Here `d` (whose env borrows the on-stack `s`) is RETURNED from `main` — an escape past `s`'s scope.
## The compiler must FAIL LOUD (build_reject) rather than emit a binary carrying a dangling env pointer.
main := fn() -> u64 {
  a := 10
  s := fn(x : u64) -> u64 { return x + a }
  d : dyn fn(u64) -> u64 = dyn_over(ptr(mut s))
  return d
}
