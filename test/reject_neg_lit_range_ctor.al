## Types §9.1/§9.2 (#602) — the same refusal through the CONVERSION-CONSTRUCTOR spelling `T(v)`.
## §9.2 names `T(v)` as one of the two forms that refine a literal's type, so `i8(-129)` is §9.1's
## literal-in-context case exactly as `n : i8 = -129` is. #564 built `ctor_lit_range_bad` for the
## positive half; it reached this program and declined one level in, on `expr_is_num_lit(arg.e)`,
## because the argument was the parser's `Unchecked(Bin(17, Num(0), Num(129)))` tree rather than a
## literal. Two independent sites answering "not a literal" about the same written value is why the
## representation, not the predicate, was the thing that had to change.
##
## Measured on the parent, this program compiled clean on all four backends and RAN TO 127.
## `unchecked i8(-129)` must STILL wrap (Concurrency §6.2) — that control is
## `accept_neg_lit_unchecked_wrap`, and it is what keeps this refusal from being over-reach.
main := fn() -> u64 {
  n := i8(-129)
  u64(unchecked bitcast(usize, i64(n)))
}
