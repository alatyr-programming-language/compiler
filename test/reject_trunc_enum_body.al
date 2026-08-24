## TRUNCATED TAIL — variant: an unclosed `enum` body. Same EOF guard, same silent product: a variant
## list truncated to nothing.
##
## MEASURED on the pre-fix compiler (f4456a4): build rc 0, the binary RAN to 42, check rc 0.
##
## POST-FIX: a located parser reject at the unclosed `{` (line 11), build rc 1 and check rc 1.
main := fn() -> u64 {
  42
}

E := enum {
