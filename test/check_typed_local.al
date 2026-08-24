## sema/§1 — a TYPED local binding (`n : u64 = 100`) must check-ACCEPT: the type annotation (u64)
## and the int literal are both int (tag 1), so no mismatch. Regression for the Try-binding fix
## (the value `check_expr(v)?` result must not corrupt the type-mismatch check). Returns 42.
main := fn() -> u64 {
  n : u64 = 40
  m : u64 = 2
  n + m
}
