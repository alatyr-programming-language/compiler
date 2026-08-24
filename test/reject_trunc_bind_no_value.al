## BALANCED TRUNCATION — a binding cut off immediately after its `:=`. Every delimiter in this file is
## closed, so the residual-delimiter-depth check at the tail of `parse_program` (which closed the
## UNBALANCED class) is structurally blind to it: nothing is left open to count.
##
## MEASURED on the pre-fix compiler (495e842): the compiler died with SIGSEGV — build rc 139, check rc
## 139 — printing NOTHING. No message, no module, no line. The cause was not a bad pointer but
## unbounded recursion: `p_factor` matched none of its branches on the end-of-input sentinel, fell
## through to its parenthesized-expression tail, stepped the cursor past the end and re-entered itself
## through `p_or`, until the stack ran out. Sixteen distinct truncations exited 139 for that one reason.
##
## POST-FIX: build rc 1 and check rc 1, with a located parser reject naming the construct whose
## right-hand side is missing and quoting the `:=` on the last line. Registered in scripts/e2e.sh with
## `build_reject_has` (a bare `build_reject` would have PASSED on the pre-fix compiler: 139 is nonzero).
main := fn() -> u64 {
  42
}

x :=
