## FND-10 / I5 / I9: the limit applies to a generic definition before any
## instantiation. The trailing body expression is Decl.value, not body_stmts.
@limits(no_unchecked)
identity := fn(T : type, x : T) -> T {
  unchecked x
}
main := fn() -> u64 { return 0 }
