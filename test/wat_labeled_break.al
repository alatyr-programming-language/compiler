## WAT bounded slice: a statement-only labeled break exits an outer loop from a nested loop.
## The inner and outer loop bodies each register one defer action. The named break must drain both
## scopes in LIFO order before branching to the outer exit: bump(2), then bump(1), yields 21.
## Labeled continue, value-bearing labeled breaks, labeled blocks, aggregate loop values, and
## bare/diverging value-loop paths remain explicit fail-loud follow-ups.
mut ACC : u64 = 0
bump := fn(n : u64) -> u64 { ACC = ACC * 10 + n ; 0 }

main := fn() -> u64 {
  @label(outer) loop {
    defer bump(1)
    loop {
      defer bump(2)
      break outer
    }
  }
  ACC
}
