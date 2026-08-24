## e2e — a `{}`-template `print` hole filled by a TUPLE var renders via structural Display. A tuple slot
## reuses `snl` for its element count (not a type span), so the emit's expr_type_span gave nothing and
## the hole was dropped; the type is now recovered by scanning the block (block_decl_type, the same
## resolver instance-collection uses). Prints "t (40, 2)" and returns 42.
main := fn() -> u64 {
  t : (u64, u64) = (40, 2)
  std::fmt::print("t {}\n", t)
  42
}
