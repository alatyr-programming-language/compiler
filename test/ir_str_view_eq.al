## e2e — #980 (IR-36): `==` and `!=` over `str` compare content, not the two views' words. Stdlib
## appendix §3.6 (STD-4): `a == b` holds when the two have equal byte length and equal bytes, and two
## distinct views of the same bytes are equal while their `ptr`s differ. The shared IR builds it as a
## length test, then a byte loop that leaves at the first difference: a difference in the last byte, a
## prefix of the other length, equal bytes in two distinct literals, and two empty views. No function
## here has a `str` in its signature, so every backend takes all of them from the IR.
## 2 + 4 + 8 + 16 = 30, + 12 = 42; any wrong answer adds 50 or more.
## expect: run 42
equal_bytes := fn() -> u64 {
  a := "fn"
  b := "fn"
  if a == b { return 2 }
  50
}

last_byte := fn() -> u64 {
  a := "fn"
  if a == "fm" { return 50 }
  if a == "fnx" { return 50 }
  4
}

shorter := fn() -> u64 {
  w := "let"
  mut r : u64 = 0
  if w != "le" { r = r + 4 }
  if w != "lex" { r = r + 4 }
  if w != "let" { r = r + 50 }
  r
}

empty := fn() -> u64 {
  e := ""
  if e != "" { return 50 }
  if e == "" { return 16 }
  50
}

main := fn() -> u64 {
  equal_bytes() + last_byte() + shorter() + empty() + 12
}
