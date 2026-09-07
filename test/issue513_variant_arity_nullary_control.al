## Issue #513 CONTROL — the two NULLARY spellings, which are the ones an arity rule can most easily
## break. The parser normalizes a parenthesis-less `E.N` to the same constructor node as `E.N()`, both
## carrying a supplied count of ZERO, so a rule that only looked at whether parentheses were written
## would reject the bare spelling every prelude enum uses. Both must stay accepted next to a
## one-payload variant of the SAME enum. Returns 20 + 20 + 2 = 42.
E := enum { N, A(u64) }

tag := fn(e : E) -> u64 {
  match e {
    N => { 20 }
    A(x) => { x }
  }
}

main := fn() -> u64 {
  bare := E.N
  par := E.N()
  one := E.A(2)
  tag(bare) + tag(par) + tag(one)
}
