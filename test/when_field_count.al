## e2e — a STRUCTURAL FIELD-COUNT `when` PREDICATE on a generic fn (Comptime §7.1/§9, CT-4/CT-5). The guard
## is the spec's `TypeInfo` surface (appendix §4.1): `typeinfo(T)` is `Struct{fields : [Field]}`, so a
## "at-least-two-fields" bound is `when typeinfo(T).fields.len >= 2` — folded PER-INSTANCE at monomorphization
## with `T` = the concrete instance type (keyed on the struct's declared FIELD COUNT).
##
## Instantiated with a 2-field STRUCT `S` → `typeinfo(S).fields.len` = 2 >= 2 → the guard folds TRUE →
## `pick__S` is emitted → builds+runs to 42. The sibling `when_field_count_reject` exercises the FALSE path
## (a 1-field struct). Generic-instance emission is x86-focused, so this is `run_x86`.
S := struct { a : u64, b : u64 }

pick := fn(T : type, x : u64) -> u64 when typeinfo(T).fields.len >= 2 { x }

main := fn() -> u64 {
  pick(S, 42)
}
