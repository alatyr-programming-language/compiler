## PLANTED DEFECT — DO NOT MERGE. This fixture is deliberately wrong: it states `run 42` and
## returns 7. It exists only to prove that the omen merge queue bisects a red batch and names the
## guilty PR (#1127). Close this PR without merging once the bisection has been observed.
main := fn() -> u64 {
  7
}
## expect: run 42
