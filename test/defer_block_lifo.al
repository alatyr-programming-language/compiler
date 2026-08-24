## DEFER (§9.3): two `defer { … }` block actions run LIFO (last registered first) as separate units.
## `f` registers block {mark(1)} then block {mark(2)}; on exit the LAST (mark(2)) runs first, then
## mark(1) → ACC (base 10) = 2 then 21. FIFO would give 12. `main` reads ACC AFTER `f` returned (the
## return value is eval'ed before the drain).
mut ACC : u64 = 0
mark := fn(n : u64) -> u64 { ACC = ACC * 10 + n ; 0 }
f := fn() -> u64 {
  defer { mark(1) }
  defer { mark(2) }
  return ACC
}
main := fn() -> u64 { _ := f() ; return ACC }