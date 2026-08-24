## BALANCED TRUNCATION — a declaration cut off right after the `fn` keyword, before its parameter list.
##
## MEASURED on the pre-fix compiler (495e842): build rc 0, the binary ran and exited 42, and `check`
## returned 0. `parse_decl` consumed `fn` and then consumed the NEXT token unconditionally as the
## opening `(` — here the end-of-input sentinel — after which the parameter loop exited immediately and
## the declaration was accepted with an empty body. Another silent accept, so another I11 violation.
##
## POST-FIX: build rc 1 and check rc 1, located at the `fn` on the last line.
main := fn() -> u64 {
  42
}

f := fn
