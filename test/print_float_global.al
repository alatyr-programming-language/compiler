## e2e — a `{}`-template `print` hole filled by a FLOAT-valued global renders via the float path (not
## its raw int bits). The hole dispatch recognizes a float global (float_lit_span of its value) and
## routes to print_one_float. Prints "F 40.5" (verified manually) and returns 42.
mut F := 40.5
main := fn() -> u64 {
  std::fmt::print("F {}\n", F)
  42
}
