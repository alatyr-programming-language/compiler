## §8.1 `@require(pred) T` validity contract — a SATISFYING construction runs (no trap). `NonZero`
## is `u32` carrying a validity contract: `is_nonzero(v)` must hold when a `NonZero` value is
## constructed via `NonZero(v)`. `5`/`7` satisfy `v != 0`, so the checked predicate passes and
## `main` returns 42. Companion `require_trap` violates it (traps); `require_unchecked` drops the
## check with a grant. Named-fn predicate; x86-only (the checked-trap emit is the x86 back end).
is_nonzero := fn(v : u32) -> bool { return v != 0 }

NonZero := @require(is_nonzero) u32

main := fn() -> u64 {
  x := NonZero(5)
  y := NonZero(7)
  return 42
}
