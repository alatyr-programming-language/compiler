## OVER-REJECT GUARD for the end-of-input containment check in `parse_program`: a file whose last
## declaration is well-formed but whose FINAL NEWLINE is missing. The last byte of this file is the
## closing `}` below — deliberately, so keep it that way if you touch the file; an editor that appends
## a newline weakens the fixture without breaking it.
##
## The containment check counts delimiter TOKENS over the whole stream, so it is indifferent to
## trailing whitespace: this file is balanced and must compile and run exactly as before. Measured
## identical on the pre-fix and post-fix compilers: build rc 0, exit 42. Registered with `run
## trailing_no_final_newline 42` in scripts/e2e.sh.
main := fn() -> u64 {
  42
}