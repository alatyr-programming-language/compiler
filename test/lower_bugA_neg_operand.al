## Regression: unary minus as a BINARY operand must NOT spuriously trap the checked-add guard.
## `-a` desugars to `Unchecked(0 - a)`, whose runtime word is a large unsigned pattern; an
## enclosing `+`/`-` must use the SIGNED overflow guard (jno), so `30 + -a` = 25 (wrapping sub)
## instead of a spurious unsigned-carry `ud2`. Expected exit: 25.
main := fn() -> u64 {
  a := u64(5)
  u64(30 + -a)
}
