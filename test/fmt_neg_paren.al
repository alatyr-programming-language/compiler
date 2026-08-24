## fmt — unary minus `-x` binds TIGHTER than every binary operator (it is a `p_factor` prefix, below
## `*`/`/`), so a `Bin` operand MUST keep its grouping parens (§5 tooling). This was a SILENT FORMATTER
## MISCOMPILE: `-(a + b)` re-emitted as `-a + b` RE-GROUPS to `(-a) + b` — a DIFFERENT program (the
## parser erases surface parens, leaving no AST node). fmt now re-inserts the parens around a low-prec
## neg operand and stays idempotent. Unary `-` wraps (unchecked). a=10, b=3:
##   p = -(a + b) = 2^64-13 ; q = -p = 13 ; r = -(a * b) = 2^64-30 ; s = -r = 30 ; q - 1 + s = 42.
main := fn() -> u64 {
  a := 10
  b := 3
  p := -(a + b)
  q := -p
  r := -(a * b)
  s := -r
  return q - 1 + s
}
