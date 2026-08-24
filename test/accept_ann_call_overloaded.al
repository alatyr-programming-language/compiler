## The guard against the overload false-reject: with two `f`s in scope the callee's return type is not
## knowable without resolving the overload set, so the rule must stay silent (`sole_fn_ret_ty` counts
## the matches and answers only when there is exactly one). A conforming same-type call must also stay
## accepted. Registered CHECK-only while `f("ok")` could not be LINKED: a `StrLit` argument matched
## every candidate as a wildcard, so the overload set stayed ambiguous, no signature suffix was emitted
## and the call became the bare label `…__f` → `undefined reference` from `ld` (exit 14, which reads
## like `b.len()` answering 14). Fixed — a string literal now binds only to a `str` parameter
## (`overload_args_match`) — so this may be promoted to `run accept_ann_call_overloaded 9`
## (`a + c` = 4 + 5); the str half is locked separately by `overload_str_literal_arg`.
f := fn(n : u64) -> u64 {
  return n
}
f := fn(s : str) -> str {
  return s
}
h := fn() -> u64 {
  return 5
}
main := fn() -> u64 {
  a : u64 = f(4)
  b : str = f("ok")
  c : u64 = h()
  return a + c
}
