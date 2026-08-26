## Issue #44 bounded WAT slice: a named continue to the nearest scalar value-bearing loop has depth 0,
## like bare continue, and resumes the loop's next iteration without carrying a value.
## Failure-first baseline parent b52d1b2: x86_64=7, WAT=134. After the fix both targets return 7.
## AArch64/RV64 are explicitly outside this focused fixture's registration; their residual sweeps remain
## unchanged and this lane makes no cross-target claim.
main := fn() -> u64 {
  mut once : u64 = 0
  x := @label(v) loop {
    once = once + 1
    if once == 1 { continue v }
    break 7
  }
  x
}
