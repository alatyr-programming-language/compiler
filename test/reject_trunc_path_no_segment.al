## BALANCED TRUNCATION — a qualified path cut off after its `::`, with no segment name following.
##
## MEASURED on the pre-fix compiler (495e842): build rc 0, the binary ran and exited 42, `check`
## returned 0. Two independent places walked the path assuming a `:: name` PAIR: the expression parser
## found no name, fell back to a bare variable and left the `::` orphaned, and the declaration-level
## import lookahead then stepped one slot PAST the end-of-input sentinel and recorded the declaration
## as a module alias whose path span ran to the end of the buffer. A silent accept from both ends.
##
## POST-FIX: build rc 1 and check rc 1, located at the `::` on the last line. The legitimate spelling
## of the same construct — a real alias with its segment present — is guarded by
## trunc_guard_fn_signature_forms, which must keep compiling.
main := fn() -> u64 {
  42
}

x := rt::
