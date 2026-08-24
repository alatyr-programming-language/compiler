## e2e (build_reject) — the FALSE branch of a structural is-KIND `when` PREDICATE (Comptime §7.1/§9,
## CT-4/CT-5). `pick(T, x)` is guarded `when match typeinfo(T) { Struct(_) => true; _ => false }` (an
## is-struct bound). Here it is instantiated with the SCALAR type `u64`, whose kind is `Scalar` (≠
## `Struct`), so the guard folds FALSE and the instance `pick__u64` is AS-IF-ABSENT — never emitted.
## `main`'s call site still references `pick__u64`, so the build fails LOUD (undefined symbol at link) —
## exactly the spec's "the declaration does not exist for this `T`". Without the instantiation-time kind
## fold this would build (the guard ignored), so a SUCCEEDING build here is the regression to catch.
pick := fn(T : type, x : u64) -> u64 when match typeinfo(T) { Struct(_) => true; _ => false } { x }

main := fn() -> u64 {
  pick(u64, 42)
}
