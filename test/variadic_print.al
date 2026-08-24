## e2e — the `{}`-template comptime-variadic `std::fmt::print` (Functions §7.1). The compiler splits
## the template literal on `{}` holes and expands the call to `io::print("<segment>")` per literal
## run + `print_one(<argtype>, <arg>)` per hole, in order — the specified `[seg0, arg0, seg1, …]`
## interleaving. Prints "40 + 2 = 42" (verified manually) and returns 42; this checks the whole
## desugar compiles, links (io::print + the collected print_one__u64 instance), and runs without
## crashing. Multi-hole; args are typed locals (their type resolved from the block's declarations).
main := fn() -> u64 {
  a : u64 = 40
  b : u64 = 2
  std::fmt::print("{} + {} = 42\n", a, b)
  42
}
