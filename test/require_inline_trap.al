## §8.1 `@require(pred) T` — inline `fn(v)` predicate. A violating explicit construction must trap,
## exactly like a named require predicate, rather than silently skipping the contract.
NonZeroI := @require(fn(v : u32) -> bool { return v != 0 }) u32

main := fn() -> u64 {
  x := NonZeroI(0)
  return 42
}
