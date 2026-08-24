## FN-6 — a call through an EXPRESSION CALLEE delivers only a single-word SCALAR result. The whole
## return-CLASS machinery (float → %xmm0, enum → discriminant + payload, wide struct → the hidden sret
## pointer) is keyed off the callee's NAME, and an expression callee has none — an `f64` result would
## be read out of %rax as raw bits and a `str` result is a two-word pair, both SILENT wrong values.
## So a non-scalar return type is a BUILD reject (`build_reject` — sema resolves no signature for the
## borrowed callee name); bind the callee to a name first, which routes it through the name-keyed
## classes (`fn_value_bound_callee`). The scalar spellings are locked by `fn_value_expr_callee`.
mkstr := fn(x : u64) -> str { return "hi" }
main := fn() -> u64 {
  gs : [fn(u64) -> str; 1] = [mkstr]
  return len(gs[0](1))
}
