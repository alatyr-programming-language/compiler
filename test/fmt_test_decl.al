## e2e/fmt — a `@test("…")` TEST DECLARATION (TOOL-5) survives a reformat. The parser keeps the
## DESCRIPTION as the declaration's "name", drops the binding name outright, and truncates the return
## type to its HEAD token (`Result` out of `Result(usize, str)`), so nothing in the AST can rebuild
## the declaration — fmt refused the WHOLE FILE with "unsupported declaration kind", which is every
## file a user writes tests in (`native_test_runner_flags`). The declaration is copied verbatim from
## the `@` through the balanced end of its body instead, so both the anonymous and the named spelling
## round-trip exactly, and the body's own `##` comments come along.
@test("named test with a Result return")
ok_case := fn() -> Result(usize, str) {
  ## a comment inside a verbatim-copied body
  return Result.Ok(0)
}

@test("a test with no return type at all")
void_case := fn() {
  x := 1
}

main := fn() -> u64 {
  return 42
}
