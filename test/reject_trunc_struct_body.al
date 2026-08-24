## TRUNCATED TAIL — variant: an unclosed `struct` body. The member loop's EOF guard ends the struct as
## if the `}` had been read, so a type with no fields is what the rest of the program would have seen.
##
## MEASURED on the pre-fix compiler (f4456a4): build rc 0, the binary RAN to 42, check rc 0.
##
## POST-FIX: a located parser reject at the unclosed `{` (line 11), build rc 1 and check rc 1.
main := fn() -> u64 {
  42
}

S := struct {
