## e2e (#428) — a store whose left operand is an INTEGER LITERAL, and the statement it used to eat.
## Memory §1.6 is normative: a store's left operand must be a place-expression, and a store onto a
## value-expression is ill-formed. Grammar §3.3 says the same structurally — `place` is rooted at an
## ident, a path or `deref(…)` — so `5 = 3` is not derivable as an assignment target at all.
##
## The compiler did not mis-LOWER this; it built no statement for it. No `*_assign_starts` recognizer
## matches a literal head, so the line fell through `stmt_starts` to the trailing-expression path,
## where `p_factor`'s final branch assumes an unrecognized token is a `(`: it took the `=` for an
## opening parenthesis, the right-hand side for the parenthesized expression, and the FOLLOWING
## STATEMENT for the closing one.
##
## That is why this fixture carries three more lines rather than a bare `5 = 3`. Measured on the
## parent (`d18fb3f`, x86_64): built rc 0 and ran to 12 — `n = 41` was swallowed as the closing
## parenthesis and never ran, so `n` was still 11 when `n = n + 1` made it 12, and the program a user
## would read as returning 42 exited 12 with a clean build and no message. A vanished line of real
## work is worse than an accepted bad program, which is why the reject must arrive earlier.
##
## The parser refuses it now, upstream of x86_64, AArch64, RISC-V64 and WAT alike; the harness asserts
## the wording and the reported line, which are deliberately not quoted here, and that no artifact
## remains. The accepting twin is value_expr_assign_place_accept.al.
main := fn() -> u64 {
  mut n : u64 = 11
  5 = 3
  n = 41
  n = n + 1
  n
}
