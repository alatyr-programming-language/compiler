## BALANCED TRUNCATION — a member access cut off after its `.`, with no field, variant or element name.
##
## MEASURED on the pre-fix compiler (495e842): build rc 0, the binary ran and exited 42, `check`
## returned 0. The postfix loop consumed the `.` and then bound the member name to the end-of-input
## sentinel — a zero-length span at the very end of the buffer — and built the access node from it, so
## the declaration was accepted with a nameless member. `x := f().` and `x := 1.` behaved the same.
##
## POST-FIX: build rc 1 and check rc 1, located at the `.` on the last line.
main := fn() -> u64 {
  42
}

x := y.
