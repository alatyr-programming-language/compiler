## e2e (build_reject) — Comptime §9.1/§9.2: a `comptime if` controlling expression MUST be
## comptime-known, and emission applies to the SELECTED branch. A condition the lower cannot fold has
## no selected branch, so it is a LOCATED REJECT (the offending source line is written to stderr).
## Before this, an unfoldable condition emitted NEITHER branch with no diagnostic at all — both arms'
## effects were silently deleted, and this program returned 5 instead of 30 or 70. `n` and `x` are
## ordinary RUNTIME locals, so `x > n` depends on a runtime value: exactly the case the spec calls a
## compile error.
main := fn() -> u64 {
  mut x : u64 = 5
  n := 3
  comptime if x > n { x = 30 } else { x = 70 }
  return x
}
