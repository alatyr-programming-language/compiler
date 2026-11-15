- The fixed-array parameter plan now derives its caller edges from the tree the emitters actually see,
  after the driver's rewrites, and not from the source text alone (#1675): a `__hoflam<N>` clone and a
  lifted lambda are callers in their own right, each tried by the fixpoint with its own answer, so a
  function is no longer held to its legacy emission on every target because some other declaration of the
  program carries a capturing closure whose text the scan could not tell apart. What the tree cannot see
  stays held — a name the emitters pick by its literal spelling, a `@convert`, an occurrence outside every
  declaration — and the text scan runs beside the walk, so where the two disagree the plan holds.
