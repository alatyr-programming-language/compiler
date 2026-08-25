## Issue #44 bounded WAT slice: a statement-only labeled continue exits a nested loop to an outer loop.
## The inner and outer loop bodies each register one defer action. The named continue must drain both
## actions in LIFO order (bump(2), then bump(1)) before the outer loop rechecks its guard.
## The guard is false on the next pass, so ACC is exactly 21.
## Value-bearing loops, labeled blocks, aggregate/value-bearing breaks, and bare/diverging value-loop
## paths remain outside this WAT slice and must stay fail-loud.
mut ACC : u64 = 0
bump := fn(n : u64) -> u64 { ACC = ACC * 10 + n ; 0 }

main := fn() -> u64 {
  mut once : u64 = 0
  @label(top) while once < 1 {
    defer bump(1)
    once = once + 1
    loop {
      defer bump(2)
      continue top
    }
  }
  ACC
}
