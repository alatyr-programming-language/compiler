## e2e — `std::fmt::print_one(T, v)` renders a value to stdout with NO trailing newline (println
## minus the newline). The per-hole renderer the `{}`-template `print` desugar builds on; also
## usable directly. `print_one(u64, 100)` writes "100" (3 bytes) and returns the write byte count.
## Returns 42 when the count is 3 (the render + write succeeded).
main := fn() -> u64 {
  n := std::fmt::print_one(u64, 100)
  if n == 3 { return 42 }
  1
}
