## e2e (#428) — a store into an element of an ARRAY CONSTRUCTOR. `[1, 2, 3]` is a value-expression
## (Memory §1.6): it names no storage the program can address, so an index chain rooted at it is not
## a `place` under Grammar §3.3 and the store has nothing to write into.
##
## A `[` head matched no statement head at all, so the line fell to the trailing-expression fallback
## and `p_factor` read the `=` as an opening parenthesis and the `7` below as its closer. Measured on
## the parent (`d18fb3f`, x86_64): built rc 0 and exited 65, with the declared `7` never reached.
##
## Refused in the parser, upstream of all four backends; the harness asserts the wording and the
## reported line, which are deliberately not quoted here, and that no artifact remains.
main := fn() -> u64 {
  [1, 2, 3][0] = 65
  7
}
