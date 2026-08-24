## e2e (RANGE-SLICE `s[lo..hi]` — a str sub-view, `Expr::Slice`). Before this, the lean parser
## had no `[a..b]` form: the postfix index consumed `..` as the closing `]`, and the leftover
## `hi]` DRIFTED the cursor — swallowing the NEXT top-level decl (the real symptom: `alloc::vec`'s
## `split` ate `filter`, so the higher-order stdlib failed to link). Now `s[lo..hi]` parses to
## `Slice(base, lo, hi)` and lowers to the {ptr = base.ptr + lo, len = hi - lo} sub-view (reusing
## the `sub`-view machinery). `t := s[0..2]` is "*b" (len 2, ptr = s.ptr); `bytes(t)[0]` = '*' = 42.
main := fn() -> u64 {
  s := "*bcd"
  t := s[0..2]
  u64(bytes(t)[0])
}
