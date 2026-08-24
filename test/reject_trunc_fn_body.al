## TRUNCATED TAIL — variant: the trailing declaration's HEAD is valid and only its BODY is cut off,
## with the body already carrying an expression. The block parser's EOF guard ends the body as if the
## `}` had been read, so the declaration parses and lowers.
##
## MEASURED on the pre-fix compiler (f4456a4): build rc 0, the binary RAN to 42, check rc 0. Note the
## EMPTY-body spelling (`f := fn() -> u64 {` with nothing after it) was already rejected pre-fix, but
## for an unrelated reason and with an unrelated message (`alatyr: check: invalid at line N`) — one
## expression inside the truncated body was enough to make the whole thing silent.
##
## POST-FIX: a located parser reject at the unclosed `{` (line 15), build rc 1 and check rc 1.
main := fn() -> u64 {
  42
}

f := fn() -> u64 { 1
