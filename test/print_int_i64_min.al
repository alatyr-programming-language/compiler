## e2e x86_64 — std::io::print_int must render the complete signed minimum without
## checked overflow. The contract is base-10, minimal digits, and a leading '-' for
## a negative two's-complement value; print_int returns the final write result (1).
main := fn() -> u64 {
  n : i64 = -9223372036854775808
  wrote := std::io::print_int(n)
  std::io::print("\n")
  if wrote == 1 { return 42 }
  1
}
