## DEFER (§9.3): a `defer` in a `while` BODY runs on `continue` (per iteration). Each pass registers
## bump(1), then `continue` drains the loop body's defers before jumping to the guard. ACC (base 10)
## accumulates 1 per iteration for 3 iterations → 111. If the continue-path defer ran only at the loop's
## final exit (not per iteration), ACC would be much smaller (e.g. 1); if dropped, 0.
mut ACC : u64 = 0
bump := fn(n : u64) -> u64 { ACC = ACC * 10 + n ; 0 }
f := fn() -> u64 {
  mut i : u64 = 0
  while i < 3 {
    defer bump(1)
    i = i + 1
    continue
  }
  return ACC
}
main := fn() -> u64 { return f() }