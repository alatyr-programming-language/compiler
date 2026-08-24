## DEFER (§9.3): a `defer` inside an `if { … }` ARM is scoped to that arm — it runs at the arm's
## FALL-THROUGH (before the code after the if), not at the whole function's exit. `f` runs bump(1)
## (deferred, inside the if-then arm) then bump(2) (after the if): bump appends `n` to ACC (base 10),
## so arm-fall-through-first gives ACC = 1 then 12 — the exit code 12 PROVES the defer ran at the arm's
## fall-through (before the post-if bump(2)). If it had been deferred to the function end instead, ACC
## would be 21 (bump(2) then bump(1)); if dropped, 2.
mut ACC : u64 = 0
bump := fn(n : u64) -> u64 { ACC = ACC * 10 + n ; 0 }
f := fn() -> u64 {
  if true {
    defer bump(1)
  }
  bump(2)
  return ACC
}
main := fn() -> u64 { return f() }