## §8.1 `@require(pred) T` validity contract — an `unchecked` grant REMOVES the check at a site
## (§8.1 "removed at a site by an `unchecked` grant"). `NonZero(0)` violates `is_nonzero`, but the
## `unchecked` scope drops the checked predicate (VERIFY_CHK false), so the construction does NOT
## trap — `main` returns 42 (a trap would give 132). Mirrors `narrow_wrap_builtin`'s unchecked path.
is_nonzero := fn(v : u32) -> bool { return v != 0 }

NonZero := @require(is_nonzero) u32

main := fn() -> u64 {
  x := unchecked { NonZero(0) }
  return 42
}
