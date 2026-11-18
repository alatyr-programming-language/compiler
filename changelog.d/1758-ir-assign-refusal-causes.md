- `alatyr ir` names the cause of a refused assignment or declaration instead of reporting `stmt Assign`
  for all of them: `assign: whole value into an out/in out aggregate parameter`, `declaration: struct or
  enum literal of a type the builder does not lay out` and the other `assign: …` / `declaration: …`
  labels, one per cause (#1758), so the IR census ranks them. Which functions build, and what they build to, is
  unchanged.
