## TRUNCATED TAIL — variant: the file ends immediately after the opening `(` of a parameter list, so
## there is no return type and no body at all. The parameter loop's EOF guard absorbs it.
##
## MEASURED on the pre-fix compiler (f4456a4): build rc 0, the binary RAN to 42, check rc 0.
##
## POST-FIX: a located parser reject at the unclosed `(` (line 11), build rc 1 and check rc 1.
main := fn() -> u64 {
  42
}

BROKEN := fn(
