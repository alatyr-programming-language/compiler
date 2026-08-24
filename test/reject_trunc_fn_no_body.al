## BALANCED TRUNCATION — a complete function SIGNATURE with no body at all.
##
## MEASURED on the pre-fix compiler (495e842): build rc 1, but the only diagnostic was the checker's
## `alatyr: check: invalid at line 5 in reject_trunc_fn_no_body` — a downstream complaint about a
## bodyless declaration, not a statement about the file being truncated, and it depended on the
## checker happening to look. The MID-FILE spelling of the same shape (see
## reject_trunc_midfile_fn_no_body) got no diagnostic at all.
##
## POST-FIX: the PARSER rejects it, build rc 1 and check rc 1, located at the last line, naming the
## absent body rather than an unspecified invalidity downstream.
main := fn() -> u64 {
  42
}

f := fn() -> u64
