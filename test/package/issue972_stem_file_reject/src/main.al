## Issue #972 — the package's ordinary root-level entry. Alone, as a manifest-less root, it runs.
main := fn() -> u64 {
  return 42
}
## expect: run 42
