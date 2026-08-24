## e2e — a `{}`-template `print` hole filled by a bare INTEGER LITERAL (`print("… {}", 42)`). An
## unconstrained int literal has no inferable slot type, so the desugar routes it to the non-generic
## `print_one_int` (default `i64`, Functions §7.1) rather than a `print_one__<T>` instance. Prints
## "the answer is 42" (verified manually) and returns 42 — checks the literal-hole path compiles,
## links (print_one_int reachable via mark_lit), and runs.
main := fn() -> u64 {
  std::fmt::print("the answer is {}\n", 42)
  42
}
