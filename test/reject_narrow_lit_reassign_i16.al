## e2e (#1473) - `i16` is a kernel integer (Types §3), so an annotated `i16` binding records its type
## and a later out-of-range write is judged against it: `y = 40000` is outside -32768..32767 and is
## refused at its line. Before #1471 `i16` was missing from `resolve_ty`'s list, the binding recorded
## no type, and the write was accepted silently. The in-range writes above it, both bounds AT their
## edges included, stay accepted.
## expect: reject "type mismatch at line 11"
main := fn() -> i64 {
  mut y : i16 = 0 - 32768
  y = 32767
  if i64(y) != 32767 { return 1 }
  y = 40000
  i64(y)
}
