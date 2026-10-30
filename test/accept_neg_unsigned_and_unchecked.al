## #1049 companion — the two halves of the rule that must NOT trap.
##
## Concurrency (spec v1.6.0) §6.5: "Over an unsigned operand the result stays unsigned and its value
## is the two's-complement negation modulo 2^N — so `-a` with `a : u64 = 5` is `2^64 − 5`, a representable value". Representable
## means there is no overflow member to guard (§6.3: "an unsigned negation or division has no overflow
## member in that set"), so the guard stays absent and the value is exact.
##
## §6.2: a programmer who wants the wrap writes `unchecked -x`. That grant is parsed separately, wraps
## the negation, and lowers guard-free — so `-MIN` under `unchecked` answers MIN and does NOT trap.
## This fixture is the proof that the fix for #1049 did not over-tighten: if it had, both of these
## would exit 132.
##
## Expected: exit 42 on every backend, no trap.
main := fn() -> u64 {
  mut a : u64 = 5
  mut n : u64 = -a                    ## unary over unsigned: 2^64-5, representable, no trap (§6.5)
  mut m : i64 = -9223372036854775807
  m = m - 1                           ## m == INT64_MIN
  mut w : i64 = unchecked -m         ## the grant is the programmer's: wraps to MIN, no trap (§6.2)
  if w != -9223372036854775808 { return 1 }
  if n != 18446744073709551611 { return 2 }
  return 42
}
