## e2e — MODULE-LEVEL string constants (`NAME := "…"`). A str is a 2-word {ptr,len} passed by
## reference, so a str-const arg is materialized like a str literal (not read as a scalar word): the
## str-temp scan counts it (so a temp block is reserved) and emit_arg resolves the const to its
## StrLit. `io::print(GREETING)` writes "hi\n" (3 bytes) and returns the count. Returns 42 = 3 + 39.
GREETING := "hi\n"
main := fn() -> u64 {
  n := std::io::print(GREETING)
  u64(n) + 39
}
