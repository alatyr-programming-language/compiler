## e2e — the `_` digit separator in integer literals (Grammar §2.4 `dec-int ::= digit { digit | "_" }`,
## SYN-3: `_` is NON-SIGNIFICANT). Before this the lexer ended the number token at the `_`, so
## `1_000` became the literal `1` and the rest was silently dropped — a SILENT WRONG VALUE.
## `dec-int` places no restriction on how many `_` or where after the first digit, so a trailing and
## a doubled separator are both well formed. Returns 42 only when every spelling equals its value.
main := fn() -> u64 {
  if 1_000 != 1000 { return 1 }
  if 1_0 != 10 { return 2 }
  if 1_0_0 != 100 { return 3 }
  if 1__0 != 10 { return 4 }
  if 1_ != 1 { return 5 }
  if 100_000 != 100000 { return 6 }
  ## a separated literal is the SAME value as its unseparated spelling, in every position
  a := 12_345
  b := 12345
  if a != b { return 7 }
  if a - b != 0 { return 8 }
  ## a tuple index is `digit { digit }` — plain decimal, unaffected by the separator scan
  t := (7, 8, 9)
  if t.0 != 7 { return 9 }
  if t.2 != 9 { return 10 }
  return 42
}
