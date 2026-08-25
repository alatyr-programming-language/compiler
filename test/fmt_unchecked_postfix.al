## fmt fixture — `unchecked` over a POSTFIX operand (Types §4.2 / §6.3). `unchecked` is a `p_factor`
## prefix that takes a PRIMARY, so it does not reach past a postfix step either: reading a raw-union
## member requires the scope, and the parenthesized member read under unchecked re-emitted WITHOUT the
## parens and became `unchecked x.u`, which re-parses as `(unchecked x).u` — the member read is back in checked mode and
## the program ran 42 -> 7. The `unchecked` operand is now always parenthesized, which is right for
## every operand shape and re-parses to the same tree. Returns 42.
U := union { s(i64), u(u64) }

main := fn() -> u64 {
  x := U.s(0 - 1)
  v := unchecked (x.u)
  if v != 18446744073709551615 { return 7 }
  return 42
}
