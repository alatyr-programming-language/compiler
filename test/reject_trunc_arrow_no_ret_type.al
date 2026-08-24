## BALANCED TRUNCATION, AND THE HEADLINE OF THE CLASS — a declaration cut off right after its return
## arrow. Unlike the SEGV shapes this one was not loud at all.
##
## MEASURED on the pre-fix compiler (495e842): build rc 0. The binary LINKED and RAN, exiting 42, and
## `alatyr check` returned 0 as well. The declaration below simply VANISHED: the return-type slot
## captured the zero-length end-of-input sentinel, the scan looking for the body `{` ran off the end,
## and the statement loop exited at once, so a well-formed-looking declaration with an empty body was
## handed back and the truncation left no trace. Invariant I11 names that the forbidden outcome — the
## program that ran was not the program that was written. (A previous lane's report gave rc 10 for this
## shape; measured directly on 495e842 it is rc 0, both by `-o out` and by `check`.)
##
## POST-FIX: build rc 1 and check rc 1, located at the arrow on the last line.
main := fn() -> u64 {
  42
}

f := fn() ->
