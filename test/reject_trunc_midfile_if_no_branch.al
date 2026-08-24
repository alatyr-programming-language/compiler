## BALANCED TRUNCATION IN THE MIDDLE OF THE FILE — an expression `if` whose braced branch never opens.
##
## MEASURED on the pre-fix compiler (495e842): build rc 139 and check rc 139, silent — the same
## unbounded-recursion crash as the tail truncations, reached by a different route: the condition
## parsed as `main`, the brace that should have followed was skipped unconditionally, and the branch
## expression then ran off the end of the token stream.
##
## POST-FIX: build rc 1 and check rc 1, located, naming the branch that never opened.
BROKEN := if

main := fn() -> u64 {
  42
}
