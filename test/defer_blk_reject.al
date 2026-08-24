## DEFER (§9.3) FAIL-LOUD: a `defer { … }` BLOCK action may NOT contain control flow (`return`/`break`/
## `continue`/`?`) — jumping out of a cleanup would skip the rest of the cleanup / jump into stale labels
## (a silent partial-cleanup hazard). This `defer { return 1 }` must be REJECTED at compile time (the
## parser's recursive block validator pans), NOT built and run. `build_reject` (any non-zero build rc)
## locks that fail-loud behavior — the alternative, a valid binary, would be the forbidden silent miscompile.
f := fn() -> u64 {
  defer { return 1 }
  return 0
}
main := fn() -> u64 { return 0 }