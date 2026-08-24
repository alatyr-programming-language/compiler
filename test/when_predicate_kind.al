## e2e — a STRUCTURAL is-KIND `when` PREDICATE on a GENERIC fn (Comptime §7.1/§9, CT-4/CT-5). The guard
## is the SPEC surface for type introspection (appendix §4.1): `typeinfo(T)` is a tagged enum inspected by
## `match`, so an is-struct bound is `match typeinfo(T) { Struct(_) => true; _ => false }` — folded
## PER-INSTANCE at monomorphization with `T` = the concrete instance type (the trait-like "generic bound
## without a trait system" lever, keyed on the type's KIND instead of its byte size).
##
## Instantiated with a STRUCT type `S` → the kind is `Struct` → the guard folds TRUE → `pick__S` is
## emitted → builds+runs to 42. The sibling `when_predicate_kind_reject` exercises the FALSE path (a
## SCALAR type → kind `Scalar` ≠ `Struct` → the instance is dropped). Generic-instance emission is
## x86-focused, so this is `run_x86` (sweep-excluded), mirroring the other `when`-guard tests.
S := struct { a : u64, b : u64 }

pick := fn(T : type, x : u64) -> u64 when match typeinfo(T) { Struct(_) => true; _ => false } { x }

main := fn() -> u64 {
  pick(S, 42)
}
