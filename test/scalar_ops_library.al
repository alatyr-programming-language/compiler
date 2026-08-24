## e2e — §2 item 3: built-in scalar arithmetic ROUTES through lib/base/num.al's @inline operators
## (typed operands, so expr_type_span resolves the width → operator_decl_idx matches num.al's `u64`
## operator, usize normalized to u64). Value-identical to the prior direct lowering. 6*7=42, -0 = 42.
main := fn() -> u64 {
  a : u64 = 6
  b : u64 = 7
  c : usize = 0
  (a * b) - c
}
