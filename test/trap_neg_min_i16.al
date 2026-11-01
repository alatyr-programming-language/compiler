## #1049 / #633 — a signed `i16` negation of `i16` MIN traps at the narrow width.
##
## Concurrency §6.1 (spec v1.6.0) puts unary `−` (negating the minimum value) in the checked-overflow
## set, and §6.5 gives the result its operand's type: over a signed operand, negating `MIN` is the
## checked failure. §6.6: no pass may introduce an `unchecked` the programmer did not write.
##
## 2^15 does not fit in `i16`, so the result must be checked against the 16-bit range, not only
## against i64. Measured on x86_64 at the parent 2cf60b45: no trap, exit 0 (the negation answered
## MIN itself). The narrow fit guard was skipped for every zero-left subtraction (`ex_is_zero_lit`),
## and the parser had wrapped `-x` in an `unchecked` the source never wrote.
##
## `m` reaches MIN through a run-time subtraction: a literal below the bound is a compile error
## (Types §9.1), and this fixture is about the run-time operation.
## Expected: TRAP (exit 132 on x86_64).
main := fn() -> i64 {
  mut m : i16 = -32767
  m = m - 1                       ## m == i16 MIN, representable: no trap here
  w := -m                         ## 2^15 is outside i16 => §6.1 trap
  if w == m { return 0 }
  return 1
}
## expect: trap
