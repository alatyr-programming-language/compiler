## e2e — a MULTI-TYPE-PARAM `when` PREDICATE (Comptime §7.1/§9, CT-4/CT-5): the guard folds `size(V)`
## against the SECOND type-parameter's concrete instance type (not the leading one). `pair(K, V, x)`
## exists only for a `V` with `size(V) <= 8`; the guard is folded PER-INSTANCE at monomorphization with
## each type-param bound to its own instance type.
##
## Instantiated with `V = u32` (size 4 <= 8) → the guard folds TRUE → `pair__u64_u32` is emitted →
## builds+runs to 42. The sibling `when_predicate_2tp_reject` exercises the FALSE path (a big `V`).
## Generic-instance emission is x86-focused, so this is `run_x86` (sweep-excluded).
pair := fn(K : type, V : type, x : u64) -> u64 when size(V) <= 8 { x }

main := fn() -> u64 {
  pair(u64, u32, 42)
}
