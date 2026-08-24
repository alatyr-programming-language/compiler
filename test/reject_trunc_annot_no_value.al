## BALANCED TRUNCATION — a TYPE-ANNOTATED module-level binding whose `= <value>` never arrives. The
## annotation parses, then the value position hits end-of-input. Delimiters balanced.
##
## MEASURED on the pre-fix compiler (495e842): build rc 139, check rc 139, silent. `x : u64 =` (the
## same shape one token further along) was identical.
##
## POST-FIX: build rc 1 and check rc 1, located at the last line.
main := fn() -> u64 {
  42
}

x : u64
