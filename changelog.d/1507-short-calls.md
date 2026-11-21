- **A whole struct read after `p.xs[j] = …` and leaf writes `p.xs[i].f = …` is no longer refused
  (#1507).** The checker discharged the element's definite-assignment marker with a call that passed
  seven arguments to a five-parameter function, so `q := p` failed `check` with `unbound name`
  although every field was written (Type System §9.4). Six more calls in the compiler's own source
  omitted a parameter (`in out nl` in three code-generator calls, an arena in two, a module span in
  a layout diagnostic) and read it from a stray register; they now pass the value in scope, and
  `defer_stmts_clean` drops a parameter it never used.
