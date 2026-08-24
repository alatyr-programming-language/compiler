## e2e — the RETURN mirror. The declared return type is likewise the context the returned literal
## takes its type from (Declarations §3.4), so `fn() -> u8 { return 300 }` is out of range. Sema
## judges it in the same recursive return walker that already checks aggregate/scalar return clashes,
## so a `return` nested in an if/while/match branch is covered too. Located at the fn (line 5).
g := fn() -> u8 {
  return 300
}

main := fn() -> i64 {
  return i64(g())
}
