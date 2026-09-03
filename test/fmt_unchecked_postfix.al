## fmt fixture — `unchecked` over a POSTFIX operand (Types §4.2 / §6.3). Reading a raw-union member
## requires the scope, and the parenthesized member read under unchecked re-emitted WITHOUT the parens
## became `unchecked x.u`; back when `unchecked` was a `p_factor` prefix taking a PRIMARY that
## re-parsed as `(unchecked x).u` — the member read back in checked mode, and the program ran
## 42 -> 7. Since #410 the operand is the POSTFIX expression, so the bare spelling would re-parse
## correctly too; the `unchecked` operand is nonetheless always parenthesized, which is still needed
## for a BINARY operand and is right for every operand shape. Returns 42.
U := union { s(i64), u(u64) }

main := fn() -> u64 {
  x := U.s(0 - 1)
  v := unchecked (x.u)
  if v != 18446744073709551615 { return 7 }
  return 42
}
