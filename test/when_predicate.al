## e2e — COMPTIME `when` PREDICATE on a GENERIC fn (Comptime §7.1/§9, CT-4/CT-5): an INLINE
## comptime-boolean over `size(T)` gates a generic fn's INSTANTIATION. `pick(T, x)` exists only for a
## type `T` with `size(T) <= 8`; the guard is folded PER-INSTANCE at monomorphization with `T` bound to
## the concrete instance type (the trait-like "generic bound without a trait system" lever).
##
## Instantiated with `u64` (size 8) → the guard folds TRUE → `pick__u64` is emitted → builds+runs to 42.
## (A broken fold that dropped this instance would leave `pick__u64` undefined → the build would fail;
## the sibling `when_predicate_reject` exercises the FALSE path — a `size(T) > 8` type is dropped.)
## The predicate is arch-independent (a byte-size fact), but generic-instance emission is x86-focused,
## so this is `run_x86` (sweep-excluded), mirroring the other `when`-guard tests.
pick := fn(T : type, x : u64) -> u64 when size(T) <= 8 { x }

main := fn() -> u64 {
  pick(u64, 42)
}
