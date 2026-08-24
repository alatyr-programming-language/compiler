## DEFER (§9.3): a fn-body `defer` + a nested-block `defer` — on `return` the NESTED (inner) one runs
## FIRST (LIFO across scopes), then the fn-body (outer) one at the epilogue. `f` registers bump(2) at the
## fn top level, then bump(1) inside the `if` arm, then returns. ACC (base 10): bump(1) then bump(2) →
## 12 proves inner-first; if outer ran first it would be 21.
mut ACC : u64 = 0
bump := fn(n : u64) -> u64 { ACC = ACC * 10 + n ; 0 }
f := fn() -> u64 {
  defer bump(2)
  if true {
    defer bump(1)
    return 0
  }
  return 1
}
main := fn() -> u64 {
  r := f()
  return ACC
}