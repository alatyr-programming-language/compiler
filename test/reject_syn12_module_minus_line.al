## e2e — Grammar §2.6 continuing tokens (SYN-12, spec 1.12.0; #1910). `-` is not a continuing token, so a
## module constant `k : i64 = 50` followed by a line `- 8` is not `50 - 8`: the `- 8` line would begin a
## new module item, and an expression is not one. The parser used to join the lines and accept.
k : i64 = 50
  - 8

main := fn() -> u64 {
  u64(k)
}
## expect: reject "unexpected token `8`" "at line 5"
