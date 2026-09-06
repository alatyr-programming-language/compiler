## e2e (#428) — a store through `bytes(s)[i]`. `bytes(s)` is a CALL: whatever it yields, Grammar §3.3
## cannot derive an assignment target that passes through a `(`, and Memory §1.6 forbids the store on
## a value-expression. This is the parse defect, not the mutability question #429 records for the
## bare `s[0] = 65` spelling, whose left side IS a place and whose parse was always correct.
##
## The call head matched no statement head, so the line fell to the trailing-expression fallback and
## `p_factor` read the `=` as an opening parenthesis and the `7` below as its closer. Measured on the
## parent (`d18fb3f`, x86_64): built rc 0 and exited 65, with the declared `7` never reached.
##
## Refused in the parser, upstream of all four backends; the harness asserts the wording and the
## reported line, which are deliberately not quoted here, and that no artifact remains.
main := fn() -> u64 {
  s := "abc"
  bytes(s)[0] = 65
  7
}
