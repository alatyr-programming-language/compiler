## Issue #44 residual: a named continue to the nearest value-bearing loop has depth 0, like bare continue.
## Failure-first baseline origin/main 88aa3a2: x86_64=7, WAT=134. PR #75 pre-amend 80a9dd4 exposed
## the regression as WAT=7; the amendment must restore WAT=134 instead of emitting `$cont`.
## AArch64/RV64 are explicitly out of this focused fixture's registration; their residual sweeps remain
## unchanged and the amendment adds no cross-target claim.
## x86_64 accepts the valid source and reaches break 7; WAT must fail loud instead of emitting `$cont`.
main := fn() -> u64 {
  mut once : u64 = 0
  x := @label(v) loop {
    once = once + 1
    if once == 1 { continue v }
    break 7
  }
  x
}
