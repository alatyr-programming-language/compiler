## e2e (build_reject) — the FALSE branch of a NAMED comptime PREDICATE `when is_small(T)` (Comptime §7.1/§9,
## CT-4). `pick(T, x)` is guarded on the predicate `is_small := fn(T : type) -> bool { size(T) <= 8 }`; here
## it is instantiated with `Big` (a 3-word struct, size 24 > 8), so the inlined predicate folds FALSE and
## the instance `pick__Big` is AS-IF-ABSENT — never emitted. `main`'s call site still references it, so the
## build fails LOUD (undefined symbol at link) — exactly the spec's "the declaration does not exist for this
## `T`". Without the named-predicate fold this would build (the guard ignored), so a SUCCEEDING build here is
## the regression to catch (`build_reject` asserts a non-zero build).
Big := struct { a : u64, b : u64, c : u64 }

is_small := fn(T : type) -> bool { size(T) <= 8 }

pick := fn(T : type, x : u64) -> u64 when is_small(T) { x }

main := fn() -> u64 {
  pick(Big, 42)
}
