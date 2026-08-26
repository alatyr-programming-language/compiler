strbuf := rt
(Expr) := ast

main := fn() -> u64 {
  value := Expr(value = 42)
  return value.value
}
