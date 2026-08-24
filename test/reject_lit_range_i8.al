## e2e — the SIGNED narrow bound of Types §9.1: `i8` holds [-128, 127], and the grammar has no
## negative literal, so 200 is out of range. Located at the binding (line 4).
main := fn() -> i64 {
  x : i8 = 200
  return i64(x)
}
