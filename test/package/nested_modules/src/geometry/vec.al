## Files under `src/geometry` form the `geometry::vec` module. `answer` is `pub` because a SIBLING
## module names it: Modules §3 — privacy flows down the tree and exposure flows up only through `pub`,
## so a non-`pub` `answer` here would be nameable by `geometry::vec` and its descendants alone, never
## by the root's other child `main`. (This fixture asserted the opposite until 2026-08-20.)
pub answer := fn() -> u64 {
  return 42
}
