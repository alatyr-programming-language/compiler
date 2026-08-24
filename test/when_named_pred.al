## e2e — a NAMED comptime PREDICATE as a generic `when`-bound (Comptime §7.1/§9, CT-4: "a constraint is
## an ordinary comptime fn(type) bool"). Instead of the guard spelling the `size(T)`/`typeinfo(T)` check
## inline, it NAMES a predicate `is_small := fn(T : type) -> bool { size(T) <= 8 }` and gates on
## `when is_small(T)`. The instantiation-time fold INLINES the predicate's single trailing bool expression
## (with the predicate's `T` bound to the call's type arg, itself resolved to the concrete instance type)
## and folds it exactly like the inline form — the trait-like "generic bound without a trait system".
##
## `pick(T, x)` exists only for a `T` with `is_small(T)`; instantiated with `u64` (size 8 <= 8) → the
## predicate folds TRUE → `pick__u64` is emitted → builds+runs to 42. The sibling `when_named_pred_reject`
## exercises the FALSE path (a big type). Generic-instance emission is x86-focused, so this is `run_x86`.
is_small := fn(T : type) -> bool { size(T) <= 8 }

pick := fn(T : type, x : u64) -> u64 when is_small(T) { x }

main := fn() -> u64 {
  pick(u64, 42)
}
