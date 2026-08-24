## DEFER (Control Flow §9.3 / Memory §5.8) — three shapes the existing defer set leaves untested:
##   (1) the cleanup ACTION reads a LOCAL. A `defer` registers the ACTION, not a snapshot of its
##       operands: the expression is evaluated at DRAIN time, so `defer bump(k)` sees k's value at the
##       scope's exit (3), never the value at registration (1).
##   (2) a `defer` in a `for` RANGE-loop body — the body is a scope per ITERATION, so it drains at each
##       iteration's fall-through (twice for `0..2`), not once at the loop's end.
##   (3) a `defer` in a `while` body nested inside an `if` arm — the innermost scope owns the drain.
## `bump` accumulates base-3 (`ACC = ACC*3 + n`), so BOTH the count and the ORDER of the cleanups show
## in the exit code: 0 -> 3 (k read at drain) -> 10 -> 31 (two for-iterations) -> 95 (the while body).
## Each defect gives a DIFFERENT number: a registration-time `k` -> 41; a for-defer that drained once
## -> 32; a dropped while-defer -> 31. NB the answer stays < 126 (the WASM sweep's WASI `proc_exit`).
mut ACC : u64 = 0
bump := fn(n : u64) -> u64 { ACC = ACC * 3 + n ; 0 }

## (1) the action reads a LOCAL — drain-time evaluation sees k = 3.
g := fn() -> u64 {
  mut k : u64 = 1
  defer bump(k)
  k = 3
  return 0
}

## (2) a `for` range-loop body registers one cleanup per iteration; each drains at that iteration's end.
h := fn() -> u64 {
  for i in 0..2 {
    defer bump(1)
  }
  return 0
}

## (3) a `while` body nested in an `if` arm — the while body's own fall-through drains it.
w := fn() -> u64 {
  mut i : u64 = 0
  if true {
    while i < 1 {
      defer bump(2)
      i = i + 1
    }
  }
  return 0
}

main := fn() -> u64 {
  z := g() + h() + w()
  return ACC + z
}
