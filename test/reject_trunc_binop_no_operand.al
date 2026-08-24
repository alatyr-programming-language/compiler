## BALANCED TRUNCATION — the file stops after a binary operator, so its right operand never arrives.
## Balanced delimiters again, hence invisible to the residual-depth check.
##
## MEASURED on the pre-fix compiler (495e842): build rc 139 and check rc 139 with no output at all
## (the same unbounded `p_factor` recursion on the end-of-input sentinel that every other
## operand-position truncation hit). The same shape with `==`, `and`, unary `-` and `not` in place of
## the `+` below behaved identically.
##
## POST-FIX: build rc 1 and check rc 1, located at the operator on the last line.
main := fn() -> u64 {
  42
}

x := 1 +
