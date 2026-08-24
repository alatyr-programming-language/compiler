## e2e (Types §9.1 / §11 + Grammar §2.4): the integer literal EXACTLY 2**63 must materialize as its
## written value, 0x8000000000000000. It did NOT — it came out as the immediate `$-8`, so
## `9223372036854775808` was a SILENT MISCOMPILE (2**63-1, 2**63+1 and 2**64-1 were all correct, which
## is what made it look like a lexer boundary case). The literal was in fact lexed and parsed
## correctly; the compiler's own decimal RENDERER (`rt::sb_uint`) guarded its recursion with `n >= 10`,
## and an ordering comparison against a LITERAL is lowered with the SIGNED setcc, so at n = 2**63 the
## guard read the value as negative, emitted one digit, and `push_int` wrote "-8".
##
## Covers the whole boundary neighbourhood in one run: 2**63 itself, its unsigned neighbours, the hex
## spelling of the same bit pattern, and the NEGATED form `-9223372036854775808` (i64::MIN), which used
## to come out as `8`. Each check contributes a distinct bit so a partial failure names itself.
main := fn() -> u64 {
  a : u64 = 9223372036854775808
  hi : u64 = 9223372036854775807
  lo : i64 = -9223372036854775808
  mut r : u64 = 0
  if a == hi + 1 { r = r + 1 }
  if a - 1 == hi { r = r + 2 }
  if a / 2 == 4611686018427387904 { r = r + 4 }
  if 18446744073709551615 - a == hi { r = r + 8 }
  if 0x8000000000000000 == a { r = r + 16 }
  if unchecked bitcast(u64, lo) == a { r = r + 32 }
  if r == 63 { return 42 }
  return r
}
