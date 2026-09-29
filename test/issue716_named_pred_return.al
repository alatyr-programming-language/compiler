## Issue #716 — the TRUE twin of `issue716_named_pred_return_reject`: the same lone-`return` predicate,
## instantiated with `u64` (size 8 <= 8), folds true and `pick__u64` is emitted. Both the parent and the
## fix run it to 42; it is here so the reject fixture cannot pass by refusing every lone-`return` body.
is_small := fn(T : type) -> bool { return size(T) <= 8 }
pick := fn(T : type, x : u64) -> u64 when is_small(T) { x }
main := fn() -> u64 {
  pick(u64, 42)
}
