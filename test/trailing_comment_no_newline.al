## OVER-REJECT GUARD for the end-of-input containment check in `parse_program`: a legitimately
## unusual file — the last thing in it is a COMMENT, and there is no newline after it. The lexer emits
## no token for a comment, so the delimiter count over the token stream is unaffected and the file is
## balanced; it must compile and run exactly as before. Measured identical on the pre-fix and post-fix
## compilers: build rc 0, exit 42. Registered with `run trailing_comment_no_newline 42` in
## scripts/e2e.sh. A `{` and a `(` appear inside the trailing comment below on purpose: a
## delimiter count taken over raw BYTES rather than tokens would see this file as truncated.
main := fn() -> u64 {
  42
}
## a trailing comment with an unmatched { and ( in it, and no newline after this line