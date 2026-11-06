## e2e (#774) - the issue's OWN program, verbatim: `p : u64 = 10` with NO `mut`, and
## `if p { … }`. Control Flow §4 says a numeric scalar is not truthy, so the condition is
## refused. The sibling fixtures all write `mut`; this one is the spelling the issue reports,
## and it is here so that the fence cannot be proven only on a spelling the issue never used.
main := fn() -> u64 {
  p : u64 = 10
  if p { return 1 }
  return 42
}
## expect: reject "a bare numeric condition is ill-formed at line 7 in issue774_if_numeric_cond_immutable"
