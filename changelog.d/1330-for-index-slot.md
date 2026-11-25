- **A `for x in xs` whose `x` reuses a name bound earlier in the function no longer overwrites a live
  local (#1330).** The loop's hidden index was placed after the earlier binding, on whichever local
  followed it, on every backend.
