## e2e — a `{}`-template `print` hole filled by an ARRAY var renders via structural Display (same
## block-scan type recovery as the tuple case). Prints "a [40, 1, 1]" and returns 42.
main := fn() -> u64 {
  a : [u64; 3] = [40, 1, 1]
  std::fmt::print("a {}\n", a)
  42
}
