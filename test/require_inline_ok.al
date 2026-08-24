## §8.1 `@require(pred) T` — inline `fn(v)` predicate. The predicate is lifted to a synthetic
## function and called at the explicit `T(v)` construction site. A satisfying value must run normally.
NonZeroI := @require(fn(v : u32) -> bool { return v != 0 }) u32

main := fn() -> u64 {
  x := NonZeroI(5)
  return 42
}
