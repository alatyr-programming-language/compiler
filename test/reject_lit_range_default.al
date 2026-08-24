## Types §9.1 / Declarations §3.4 — a bare integer literal with no annotation
## defaults to the target's native signed integer. 2^63 fits the parser's
## 64-bit token but is outside the default i64 range, so the binding must be
## rejected at its own source location rather than silently becoming i64::MIN.
main := fn() -> i64 {
  x := 9223372036854775808
  return 0
}
