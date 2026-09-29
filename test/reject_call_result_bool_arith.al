## #726 / Types §4.2, §4.3 — a call's result has its callee's declared type, and `bool` to an integer
## is the numeric class, always explicit, so a `bool`-returning call is not an arithmetic operand. The
## parent accepted this and ran it to 42: `check_expr`'s `Call` arm, which answers the declared result
## type, had never run, so the operand was UNKNOWN. `u64(ready()) + 41` is the conforming spelling.
ready := fn() -> bool { true }

main := fn() -> u64 {
  return ready() + 41
}
