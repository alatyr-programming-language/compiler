## PROBE — not a landing candidate. Measures what the compiler does TODAY with unary `−` on a
## signed value equal to MIN, which spec §6.1 places in the checked-overflow set by name
## ("unary `−` (negating the minimum value)"), §6.4 scopes to `neg` on `iN`, Stdlib §4.4 fixes
## the trap condition at `a == MIN`, and Arch §— maps it onto the target's `neg`.
##
## The compiler cannot express that today: the parser desugars `-x` to `Unchecked(Bin(17, 0, x))`
## (src/parser.al:1490) and lowering then suppresses the guard by SHAPE — `expr_is_zero(l)`
## (src/lower/ir.al:363) — so a negation carries no guard on ANY type, signed included. `OpNeg`
## exists in the IR signature (src/ir.al:62) with no emission arm on any backend.
##
## Conformant answer: TRAP, exit 132 (`ud2` before the operation, CG-13).
## A wrap answers MIN, whose low byte is 0 — so exit 0 is the bug, and the two are unambiguous.
neg := fn(x : i64) -> i64 { return -x }

main := fn() -> i64 {
  mut m : i64 = -9223372036854775807
  m = m - 1                       ## m == INT64_MIN, representable: no trap here
  return neg(m)                  ## +2^63 is NOT representable in i64 ⇒ §6.1 TRAP
}
