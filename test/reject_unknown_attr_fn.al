## e2e — the same §2.3 rule with the attribute prefixing a FUNCTION declaration (line 7), the other
## position the parser's prefix loop swallowed silently.
helper := fn(x : i64) -> i64 {
  return x + 1
}

@inlien
main := fn() -> i64 {
  return helper(41)
}
