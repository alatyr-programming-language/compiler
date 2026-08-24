## sema — `atomic::load` accepts only relaxed/acquire/seq_cst (spec ch.110 §2); `release` is illegal.
mut X := 0
main := fn() -> u64 {
  p := ptr(X)
  atomic::load(p, Ordering.release)
}
