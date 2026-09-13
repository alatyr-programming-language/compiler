## e2e — issue #693, position 4 of 7: the same access as a BINARY OPERAND.
##
## This row is one of the two that make the defect a wrong VALUE rather than a missing diagnostic.
## Parent verdict: check 0, build 0, exit **5**. Five is `0 + 5`, so the read really did answer zero
## on a value whose payload words are 11 and 22 — the number, not the absence of a message, is the
## evidence. The exit code is read outside any pipeline.
E := enum { A, B(u64, u64) }
main := fn() -> u64 {
  v := E.B(11, 22)
  v.a + 5
}
