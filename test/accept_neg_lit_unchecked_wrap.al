## Concurrency §6.2 (#602) — the `unchecked` control for the §9.1 negative-literal refusal. §6.2
## grants the wrapping evaluation "inside an `unchecked` scope", at "the programmer's" granularity,
## so `unchecked i8(-129)` must REMAIN accepted and must still produce the wrapped value. The
## refusal #602 asks for is about the CHECKED spelling only, and CG-7 is the reason the constructor
## walk threads a verification mode instead of refusing in `check_expr`.
##
## This is also the control that proves the parser's normalisation did not silently cancel a grant:
## the folded `Num(-129)` reaches the constructor with the same value it had as a subtraction from
## zero, and only the CHECK in front of it is mode-dependent. The wrapped value is asserted, not
## merely the acceptance — 127 is the number the parent produced for the CHECKED spelling too, so
## an assertion that only said "accepted" would pass on a compiler that never learned the rule.
##
## The exit code is 42, not the value: a cross-backend fixture must return below 126 (WASI
## `proc_exit` rejects anything else) and 127 is above it.
main := fn() -> u64 {
  n := unchecked i8(-129)
  m := unchecked i8(-130)
  if i64(n) != 127 { return 1 }
  if i64(m) != 126 { return 2 }
  return 42
}
