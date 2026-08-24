## e2e — `{{`/`}}` brace escapes in a `{}`-template `print` (Functions §7.1: a doubled brace is a
## literal `{`/`}`, NOT a hole, and consumes no argument). `print("set {{x}} = {}\n", n)` renders
## "set {x} = 7" — the escapes pass through, the single `{}` fills from `n`. Prints it (verified
## manually) and returns 42 — checks the escape run-splitting + hole counting.
main := fn() -> u64 {
  n : u64 = 7
  std::fmt::print("set {{x}} = {}\n", n)
  42
}
