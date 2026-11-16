- The fixed-array parameter plan now derives its caller edges from the tree the emitters actually see,
  after the driver's rewrites, and not from the source text alone (#1675): a `__hoflam<N>` clone and a
  lifted lambda are callers in their own right, each tried by the fixpoint with its own answer, and a
  call the text scan cannot attribute to the declaration that makes it — an index or iterator desugar, a
  call inside a clone whose callee's name is in no source file — now reaches the plan as an edge of its
  own. No function is freed by this today: the walk only ever adds edges, and where the walk and the scan
  disagree the plan holds, so every program selects exactly what it selected before. What the tree cannot
  see stays held and stays with the text scan — a name the emitters pick by its literal spelling, a
  `@convert`, an occurrence outside every declaration.
