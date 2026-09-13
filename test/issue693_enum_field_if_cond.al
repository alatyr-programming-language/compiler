## e2e — issue #693, position 6 of 7: the same access inside an `if` CONDITION.
##
## The second of the two rows that make this a wrong value. Parent verdict: check 0, build 0, exit
## **7** — the `== 0` comparison answered TRUE on a `B(11, 22)` value, so the branch was chosen by a
## word the program never wrote. Had the condition been judged on the real value the program would
## have fallen through to 42, and 7 versus 42 is what separates a fabricated zero from a stable one.
##
## This position is also why the refusal is not gated on the operand walk's `fldck` flag: that flag
## narrows the COLLISION-BLIND field-NAME fence (#508's measured residual), and this question never
## consults a member table.
E := enum { A, B(u64, u64) }
main := fn() -> u64 {
  v := E.B(11, 22)
  if v.a == 0 { return 7 }
  42
}
